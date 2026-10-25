import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';
import '../utils/file_helper.dart';
import '../utils/io_helper_stub.dart'
    if (dart.library.html) '../utils/io_helper_web.dart'
    if (dart.library.io) '../utils/io_helper_io.dart';

/// Smart Incremental Backup & Recovery Service.
///
/// Features:
/// 1. Stable single-file backup (`HaroonTailor_Backup.zip`) with atomic replacement.
/// 2. Canonical URL deduplication — avoids duplicate photo downloads and duplicate entries in ZIP.
/// 3. Incremental photo reuse — reuses unchanged photos from previous backup ZIP and local cache.
/// 4. Concurrent download pool — downloads missing photos in parallel batches.
/// 5. Complete settings preservation — shop profile, clothing types, templates, rates, theme,
///    measurement units, and delivery days are 100% backed up and restored.
/// 6. Reliable recovery — verified before saving, full backward compatibility.
class ZipBackupService {
  /// Creates an optimized, incremental single-file ZIP backup containing:
  /// - `backup.json`: Orders, customers, naap measurements, and all shop settings.
  /// - `photos/`: Unique photo files (deduplicated, incrementally reused).
  static Future<Uint8List> createZipBackup({
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Loading database records and settings...', 0.05);

    // 1. Fetch all data and settings from local storage
    final orders = await LocalStorageService.getCachedOrders();
    final customers = await LocalStorageService.getCachedCustomers();
    final settings = await LocalStorageService.getCachedShopSettings() ?? {};
    final garmentTypes = await LocalStorageService.getGarmentTypes();
    final messageTemplates = await LocalStorageService.getMessageTemplates();
    final defaultRates = await LocalStorageService.getDefaultRates();
    final appTheme = await LocalStorageService.getAppTheme();
    final appLanguage = await LocalStorageService.getAppLanguage();
    final measurementUnit = await LocalStorageService.getMeasurementUnit();
    final defaultDeliveryDays = await LocalStorageService.getDefaultDeliveryDays();
    final notesSuggestions = await LocalStorageService.getNotesSuggestions();
    final isAutoBackup = await LocalStorageService.isAutoBackupEnabled();
    final autoBackupFreq = await LocalStorageService.getAutoBackupFrequency();

    // 2. Collect all customer measurements
    final Map<String, dynamic> customerMeasurementsMap = {};
    int totalMeasurements = 0;
    if (customers != null) {
      for (var c in customers) {
        if (c is Map && c['id'] != null) {
          final cid = (c['id'] as num?)?.toInt() ?? int.tryParse(c['id'].toString()) ?? 0;
          if (cid > 0) {
            final meas = await LocalStorageService.getCustomerMeasurementsOffline(cid);
            if (meas.isNotEmpty) {
              customerMeasurementsMap['$cid'] = meas;
              totalMeasurements += meas.length;
            }
          }
        }
      }
    }

    // 3. Process orders with canonical URL deduplication
    final List<dynamic> detailedOrders = [];
    final Map<String, String> photoPathMap = {}; // originalUrlOrData -> canonicalZipPath
    final Map<String, Uint8List> bundledImages = {}; // canonicalZipPath -> bytes
    int totalRawPhotoRefs = 0;

    if (orders != null) {
      for (var o in orders) {
        if (o is Map && o['id'] != null) {
          final det = await LocalStorageService.getCachedOrderDetails(o['id'] as int);
          final orderData = Map<String, dynamic>.from(det ?? o);

          List<dynamic> items = [];
          if (orderData['raw_items'] is List) {
            items = List<dynamic>.from(orderData['raw_items'] as List);
          } else if (orderData['items'] is List) {
            items = List<dynamic>.from(orderData['items'] as List);
          } else if (o['raw_items'] is List) {
            items = List<dynamic>.from(o['raw_items'] as List);
          } else if (o['items'] is List) {
            items = List<dynamic>.from(o['items'] as List);
          }

          if (orderData['items'] is String) {
            orderData['items_summary'] = orderData['items'];
          }

          // 3.1 Items photo deduplication
          for (int i = 0; i < items.length; i++) {
            if (items[i] is Map) {
              final itemMap = Map<String, dynamic>.from(items[i]);
              final origUrl = (itemMap['image_path_original'] ?? itemMap['image_path'] ?? '').toString().trim();

              if (origUrl.isNotEmpty) {
                totalRawPhotoRefs++;
                final zipPath = getCanonicalZipPath(origUrl);
                if (zipPath.isNotEmpty) {
                  photoPathMap[origUrl] = zipPath;
                  itemMap['image_path_original'] = origUrl;
                  itemMap['image_path'] = zipPath;
                }
              }

              final meas = itemMap['measurements'] as Map<String, dynamic>? ?? {};
              totalMeasurements += meas.length;
              items[i] = itemMap;
            }
          }

          // 3.2 Top-level order image_path deduplication
          final topImgStr = (orderData['image_path_original'] ?? orderData['image_path'] ?? o['image_path'] ?? '').toString().trim();
          if (topImgStr.isNotEmpty) {
            final parts = topImgStr.split(',');
            final List<String> updatedTopPaths = [];
            for (var part in parts) {
              final p = part.trim();
              if (p.isEmpty) continue;
              totalRawPhotoRefs++;
              final zipPath = getCanonicalZipPath(p);
              if (zipPath.isNotEmpty) {
                photoPathMap[p] = zipPath;
                updatedTopPaths.add(zipPath);
              }
            }
            if (updatedTopPaths.isNotEmpty) {
              orderData['image_path_original'] = topImgStr;
              orderData['image_path'] = updatedTopPaths.join(',');
            }
          }

          // 3.3 Cloth photos deduplication
          final clothPhotos = LocalStorageService.sanitizePhotoList(orderData['cloth_photos'] ?? o['cloth_photos']);
          if (clothPhotos.isNotEmpty) {
            final List<String> updatedClothPhotos = [];
            for (var pStr in clothPhotos) {
              final cleanStr = pStr.trim();
              if (cleanStr.isEmpty) continue;
              totalRawPhotoRefs++;
              final zipPath = getCanonicalZipPath(cleanStr);
              if (zipPath.isNotEmpty) {
                photoPathMap[cleanStr] = zipPath;
                updatedClothPhotos.add(zipPath);
              }
            }
            if (updatedClothPhotos.isNotEmpty) {
              orderData['cloth_photos'] = updatedClothPhotos;
            }
          }

          orderData['items'] = items;
          if (orderData.containsKey('raw_items')) {
            orderData['raw_items'] = items;
          }
          detailedOrders.add(orderData);
        }
      }
    }

    final uniqueZipPaths = photoPathMap.values.toSet();
    final totalUniquePhotos = uniqueZipPaths.length;

    onProgress?.call(
      'Indexed $totalUniquePhotos unique photos (from $totalRawPhotoRefs references). Checking cache...',
      0.15,
    );

    // 4. Incremental Photo Reuse: Check existing backup ZIP and local storage
    final Map<String, List<int>> existingPhotosInZip = {};
    try {
      final existingZipBytes = await FileHelper.getExistingBackupZip();
      if (existingZipBytes != null && existingZipBytes.isNotEmpty) {
        final existingArchive = ZipDecoder().decodeBytes(existingZipBytes);
        for (var file in existingArchive) {
          if (file.isFile && file.name.startsWith('photos/')) {
            existingPhotosInZip[file.name] = file.content as List<int>;
          }
        }
      }
    } catch (_) {}

    int reusedFromZip = 0;
    int reusedFromLocal = 0;

    for (var entry in photoPathMap.entries) {
      final orig = entry.key;
      final zipPath = entry.value;

      if (bundledImages.containsKey(zipPath)) continue;

      // 4.1 Reuse from existing backup ZIP
      if (existingPhotosInZip.containsKey(zipPath)) {
        bundledImages[zipPath] = Uint8List.fromList(existingPhotosInZip[zipPath]!);
        reusedFromZip++;
        continue;
      }

      // 4.2 Decode embedded base64 data
      if (orig.startsWith('data:image')) {
        try {
          final b64 = orig.split(',').last;
          bundledImages[zipPath] = base64Decode(b64);
          continue;
        } catch (_) {}
      }

      // 4.3 Check local disk storage
      try {
        final localBytes = await readLocalPhotoFile(zipPath);
        if (localBytes != null && localBytes.isNotEmpty) {
          bundledImages[zipPath] = localBytes;
          reusedFromLocal++;
          continue;
        }
      } catch (_) {}
    }

    // 5. Identify missing photos to download from cloud
    final List<MapEntry<String, String>> missingToDownload = [];
    for (var entry in photoPathMap.entries) {
      final orig = entry.key;
      final zipPath = entry.value;
      if (!bundledImages.containsKey(zipPath)) {
        if (orig.startsWith('http://') || orig.startsWith('https://')) {
          if (!missingToDownload.any((m) => m.value == zipPath)) {
            missingToDownload.add(entry);
          }
        }
      }
    }

    final reusedTotal = reusedFromZip + reusedFromLocal;
    int downloadedCount = 0;
    int failedCount = 0;

    // 6. Download genuinely new/missing photos with concurrent pool
    if (missingToDownload.isNotEmpty) {
      onProgress?.call(
        'Reusing $reusedTotal cached photos. Downloading ${missingToDownload.length} new photos...',
        0.25,
      );

      const poolSize = 5;
      for (int i = 0; i < missingToDownload.length; i += poolSize) {
        final chunk = missingToDownload.sublist(
          i,
          (i + poolSize > missingToDownload.length) ? missingToDownload.length : i + poolSize,
        );

        await Future.wait(chunk.map((item) async {
          try {
            final response = await http.get(Uri.parse(item.key)).timeout(
              const Duration(seconds: 12),
            );
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              bundledImages[item.value] = response.bodyBytes;
              // Save to local cache in background for future instant access
              savePhotoToLocal(filePath: item.value, bytes: response.bodyBytes).ignore();
            } else {
              failedCount++;
            }
          } catch (_) {
            failedCount++;
          } finally {
            downloadedCount++;
            final progress = 0.25 + (0.55 * downloadedCount / missingToDownload.length);
            onProgress?.call(
              'Downloading new photo $downloadedCount/${missingToDownload.length}...',
              progress,
            );
          }
        }));
      }
    } else {
      onProgress?.call(
        'All $totalUniquePhotos photos already cached! Skipping network downloads...',
        0.80,
      );
    }

    onProgress?.call('Building backup data and settings...', 0.85);

    // 7. Assemble backup.json with complete database records and shop settings
    final Map<String, dynamic> backupData = {
      'app': 'Haroon Tailor',
      'version': '1.1.0',
      'backup_type': 'smart_incremental_zip',
      'export_timestamp': DateTime.now().toIso8601String(),
      'total_customers': customers?.length ?? 0,
      'total_orders': detailedOrders.length,
      'total_unique_photos': totalUniquePhotos,
      'bundled_photos': bundledImages.length,
      'reused_photos': reusedTotal,
      'downloaded_photos': downloadedCount,
      'failed_photos': failedCount,
      'total_measurements': totalMeasurements,
      // Complete settings preservation
      'settings': settings,
      'clothing_types': garmentTypes,
      'message_templates': messageTemplates,
      'default_rates': defaultRates,
      'app_theme': appTheme,
      'app_language': appLanguage,
      'measurement_unit': measurementUnit,
      'default_delivery_days': defaultDeliveryDays,
      'notes_suggestions': notesSuggestions,
      'auto_backup_enabled': isAutoBackup,
      'auto_backup_frequency': autoBackupFreq,
      // Database entities
      'customers': customers ?? [],
      'customer_measurements': customerMeasurementsMap,
      'orders': detailedOrders,
    };

    onProgress?.call('Compressing single backup archive...', 0.90);

    // 8. Create ZIP archive
    final archive = Archive();
    final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
    final jsonBytes = utf8.encode(jsonString);
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));

    for (var entry in bundledImages.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }

    final zipBytes = ZipEncoder().encode(archive);
    final result = Uint8List.fromList(zipBytes);

    // 9. Validate archive before returning
    final verifyArchive = ZipDecoder().decodeBytes(result, verify: true);
    final hasBackupJson = verifyArchive.files.any((f) => f.name == 'backup.json');
    if (!hasBackupJson) {
      throw Exception('Generated backup archive failed validation: backup.json missing');
    }

    final sizeStr = _formatBytes(result.length);
    onProgress?.call(
      '✅ Backup ready! $sizeStr ($totalUniquePhotos unique photos, $reusedTotal reused)',
      1.0,
    );

    return result;
  }

  /// Restores data and settings from a backup ZIP file.
  /// 1. Validates archive integrity.
  /// 2. Extracts photos to local storage.
  /// 3. Restores shop settings, rates, templates, garment types, theme, units.
  /// 4. Imports orders, naap measurements, and customers into LocalStorageService.
  static Future<Map<String, dynamic>> restoreFromZip({
    required Uint8List zipBytes,
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Opening & validating backup ZIP...', 0.0);

    try {
      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      onProgress?.call('Extracting files from backup...', 0.1);

      String? jsonContent;
      final Map<String, Uint8List> photos = {};

      for (var file in archive) {
        if (file.isFile) {
          if (file.name == 'backup.json') {
            jsonContent = utf8.decode(file.content as List<int>);
          } else if (file.name.startsWith('photos/')) {
            photos[file.name] = Uint8List.fromList(file.content as List<int>);
          }
        }
      }

      if (jsonContent == null) {
        return {'success': false, 'error': 'backup.json not found in ZIP file'};
      }

      onProgress?.call('Parsing backup data & settings...', 0.2);
      final data = jsonDecode(jsonContent);
      if (data is! Map<String, dynamic>) {
        return {'success': false, 'error': 'Invalid backup JSON format'};
      }

      // 1. Save extracted photos to local storage directory
      int savedPhotos = 0;
      String localPhotosDir = '';

      if (photos.isNotEmpty) {
        onProgress?.call('Saving ${photos.length} photos locally...', 0.3);
        try {
          localPhotosDir = await getLocalPhotosDirectory();
          final isNativeDir = localPhotosDir.isNotEmpty && localPhotosDir != '/web_photos';
          if (isNativeDir) {
            await createLocalDirectory(dirPath: '$localPhotosDir/photos');
          }

          for (var entry in photos.entries) {
            try {
              final targetPath = isNativeDir ? '$localPhotosDir/${entry.key}' : entry.key;
              await savePhotoToLocal(filePath: targetPath, bytes: entry.value);
              savedPhotos++;
            } catch (_) {}
          }
        } catch (_) {}
      }

      // 2. Restore all shop settings & preferences
      onProgress?.call('Restoring shop settings & preferences...', 0.5);

      try {
        if (data['settings'] is Map) {
          await LocalStorageService.saveShopSettings(Map<String, dynamic>.from(data['settings']));
        }
        if (data['clothing_types'] is List) {
          await LocalStorageService.saveGarmentTypes(List<String>.from(data['clothing_types']));
        }
        if (data['message_templates'] is Map) {
          await LocalStorageService.saveMessageTemplates(Map<String, String>.from(data['message_templates']));
        }
        if (data['default_rates'] is Map) {
          final rates = (data['default_rates'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          );
          await LocalStorageService.saveDefaultRates(rates);
        }
        if (data['app_theme'] is String && (data['app_theme'] as String).isNotEmpty) {
          await LocalStorageService.saveAppTheme(data['app_theme'] as String);
        }
        if (data['app_language'] is String && (data['app_language'] as String).isNotEmpty) {
          await LocalStorageService.saveAppLanguage(data['app_language'] as String);
        }
        if (data['measurement_unit'] is String && (data['measurement_unit'] as String).isNotEmpty) {
          await LocalStorageService.saveMeasurementUnit(data['measurement_unit'] as String);
        }
        if (data['default_delivery_days'] is int) {
          await LocalStorageService.saveDefaultDeliveryDays(data['default_delivery_days'] as int);
        } else if (data['default_delivery_days'] is num) {
          await LocalStorageService.saveDefaultDeliveryDays((data['default_delivery_days'] as num).toInt());
        }
        if (data['notes_suggestions'] is List) {
          await LocalStorageService.saveNotesSuggestions(List<String>.from(data['notes_suggestions']));
        }
        if (data['auto_backup_enabled'] is bool) {
          await LocalStorageService.setAutoBackupEnabled(data['auto_backup_enabled'] as bool);
        }
        if (data['auto_backup_frequency'] is String && (data['auto_backup_frequency'] as String).isNotEmpty) {
          await LocalStorageService.setAutoBackupFrequency(data['auto_backup_frequency'] as String);
        }
      } catch (settingsErr) {
        debugPrint('Settings restore non-fatal warning: $settingsErr');
      }

      // 3. Map orders photo paths to local storage
      onProgress?.call('Restoring orders & customers...', 0.65);
      final ordersRaw = data['orders'];
      if (ordersRaw is List) {
        for (var o in ordersRaw) {
          if (o is Map) {
            List<dynamic> items = [];
            if (o['raw_items'] is List) {
              items = o['raw_items'] as List;
            } else if (o['items'] is List) {
              items = o['items'] as List;
            }

            for (var item in items) {
              if (item is Map) {
                final zipPath = item['image_path']?.toString() ?? '';
                if (zipPath.startsWith('photos/')) {
                  if (localPhotosDir.isNotEmpty && localPhotosDir != '/web_photos') {
                    item['image_path'] = '$localPhotosDir/$zipPath';
                  } else {
                    item['image_path'] = zipPath;
                  }
                }
              }
            }

            // Top-level image_path
            final topZipPath = o['image_path']?.toString() ?? '';
            if (topZipPath.isNotEmpty) {
              final parts = topZipPath.split(',');
              final List<String> restoredTopPaths = [];
              for (var zp in parts) {
                zp = zp.trim();
                if (zp.startsWith('photos/')) {
                  if (localPhotosDir.isNotEmpty && localPhotosDir != '/web_photos') {
                    restoredTopPaths.add('$localPhotosDir/$zp');
                  } else {
                    restoredTopPaths.add(zp);
                  }
                } else if (zp.isNotEmpty) {
                  restoredTopPaths.add(zp);
                }
              }
              if (restoredTopPaths.isNotEmpty) {
                o['image_path'] = restoredTopPaths.join(',');
              }
            }

            // Cloth photos
            final clothPhotos = LocalStorageService.sanitizePhotoList(o['cloth_photos']);
            if (clothPhotos.isNotEmpty) {
              final List<String> restoredCloth = [];
              for (var cp in clothPhotos) {
                final clean = cp.trim();
                if (clean.startsWith('photos/')) {
                  if (localPhotosDir.isNotEmpty && localPhotosDir != '/web_photos') {
                    restoredCloth.add('$localPhotosDir/$clean');
                  } else {
                    restoredCloth.add(clean);
                  }
                } else if (clean.isNotEmpty) {
                  restoredCloth.add(clean);
                }
              }
              o['cloth_photos'] = restoredCloth;
            }
          }
        }
      }

      // 4. Import orders, customers, naap measurements into LocalStorageService
      onProgress?.call('Importing all records into local cache...', 0.85);
      final result = await LocalStorageService.importMasterBackupMap(data);

      onProgress?.call('✅ Restore complete!', 1.0);

      return {
        'success': result['success'] ?? false,
        'customers_count': result['customers_count'] ?? 0,
        'orders_count': result['orders_count'] ?? 0,
        'photos_count': result['photos_count'] ?? 0,
        'photos_saved_locally': savedPhotos,
        'measurements_count': result['measurements_count'] ?? 0,
        'error': result['error'],
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Generates a deterministic canonical ZIP path for any URL or local path.
  /// Prevents duplicate entries when the same photo is referenced across items,
  /// top-level orders, and cloth photos.
  static String getCanonicalZipPath(String rawUrlOrPath) {
    final clean = rawUrlOrPath.trim();
    if (clean.isEmpty) return '';

    if (clean.startsWith('photos/') || clean.startsWith('/photos/')) {
      return clean.replaceFirst(RegExp(r'^/+'), '');
    }

    final ext = _getExtension(clean);

    // If Cloudinary or web URL
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      final uri = Uri.tryParse(clean);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        final lastSeg = uri.pathSegments.last;
        final dotIdx = lastSeg.lastIndexOf('.');
        final nameOnly = dotIdx != -1 ? lastSeg.substring(0, dotIdx) : lastSeg;
        final cleanName = nameOnly.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        if (cleanName.isNotEmpty) {
          final shortHash = _hashString(clean).substring(0, 6);
          return 'photos/${shortHash}_$cleanName$ext';
        }
      }
    }

    // Base64 data URL
    if (clean.startsWith('data:image')) {
      final shortHash = _hashString(clean);
      return 'photos/b64_$shortHash$ext';
    }

    // Local device path
    final shortHash = _hashString(clean);
    return 'photos/img_$shortHash$ext';
  }

  static String _hashString(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _getExtension(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '.jpg';
    final path = uri.path.toLowerCase();
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.jpeg')) return '.jpeg';
    return '.jpg';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Runs auto-backup if enabled and interval has passed (e.g. daily).
  /// Updates the single stable backup ZIP atomically.
  static Future<bool> checkAndPerformAutoBackup({bool force = false}) async {
    try {
      final isEnabled = await LocalStorageService.isAutoBackupEnabled();
      if (!isEnabled && !force) return false;

      final lastTimeStr = await LocalStorageService.getLastAutoBackupTime();
      final todayStr = DateTime.now().toIso8601String().split('T').first;

      if (!force && lastTimeStr != null && lastTimeStr.startsWith(todayStr)) {
        return false; // Already backed up today
      }

      final zipBytes = await createZipBackup();
      final savedPath = await FileHelper.saveStableBackupZip(zipBytes: zipBytes);
      if (savedPath != null && savedPath.isNotEmpty) {
        await LocalStorageService.recordBackupSuccess(
          path: savedPath,
          sizeBytes: zipBytes.length,
        );
      }
      await LocalStorageService.recordAutoBackupTime();
      return true;
    } catch (_) {
      return false;
    }
  }
}
