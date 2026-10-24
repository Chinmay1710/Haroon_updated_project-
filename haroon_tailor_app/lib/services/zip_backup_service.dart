import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';
import '../utils/file_helper.dart';
import '../utils/io_helper_stub.dart'
    if (dart.library.html) '../utils/io_helper_web.dart'
    if (dart.library.io) '../utils/io_helper_io.dart';

/// Service to create and restore self-contained ZIP backup files
/// containing both JSON data and embedded photos (no Cloudinary needed).
class ZipBackupService {
  /// Creates a complete ZIP backup archive containing:
  /// - backup.json (all orders, customers, measurements, settings)
  /// - photos/ folder with all item images downloaded from Cloudinary or local storage
  ///
  /// Returns the ZIP file as bytes.
  static Future<Uint8List> createZipBackup({
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Preparing backup data...', 0.0);

    // 1. Get all data from local storage
    final orders = await LocalStorageService.getCachedOrders();
    final customers = await LocalStorageService.getCachedCustomers();
    final settings = await LocalStorageService.getCachedShopSettings();
    final garmentTypes = await LocalStorageService.getGarmentTypes();
    final messageTemplates = await LocalStorageService.getMessageTemplates();
    final defaultRates = await LocalStorageService.getDefaultRates();

    // 2. Collect all detailed orders with measurements & photos
    final List<dynamic> detailedOrders = [];
    final List<_ImageEntry> remoteImageEntries = [];
    final Map<String, Uint8List> bundledImages = {};
    int totalPhotos = 0;
    int totalMeasurements = 0;

    if (orders != null) {
      for (var o in orders) {
        if (o is Map && o['id'] != null) {
          final det = await LocalStorageService.getCachedOrderDetails(o['id'] as int);
          final orderData = Map<String, dynamic>.from(det ?? o);

          // In list summary, 'items' may be a String (e.g. "2x Kurta, 2x Pajama")
          // while 'raw_items' or detail 'items' is the actual List<dynamic>
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

          for (int i = 0; i < items.length; i++) {
            if (items[i] is Map) {
              final itemMap = Map<String, dynamic>.from(items[i]);
              final imageUrl = itemMap['image_path']?.toString() ?? '';
              final orderId = orderData['id'] ?? o['id'];

              if (imageUrl.isNotEmpty) {
                if (imageUrl.startsWith('data:image')) {
                  // Direct base64 image data
                  try {
                    final b64 = imageUrl.split(',').last;
                    final bytes = base64Decode(b64);
                    final photoFileName = 'photos/order_${orderId}_item_$i.jpg';
                    bundledImages[photoFileName] = bytes;
                    itemMap['image_path'] = photoFileName;
                    totalPhotos++;
                  } catch (_) {}
                } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
                  // Remote Cloudinary or web URL
                  final ext = _getExtension(imageUrl);
                  final photoFileName = 'photos/order_${orderId}_item_$i$ext';

                  remoteImageEntries.add(_ImageEntry(
                    url: imageUrl,
                    zipPath: photoFileName,
                    orderId: orderId,
                    itemIndex: i,
                  ));

                  itemMap['image_path_original'] = imageUrl;
                  itemMap['image_path'] = photoFileName;
                  totalPhotos++;
                } else {
                  // Local file path
                  try {
                    final bytes = await readLocalPhotoFile(imageUrl);
                    if (bytes != null && bytes.isNotEmpty) {
                      final ext = _getExtension(imageUrl);
                      final photoFileName = 'photos/order_${orderId}_item_$i$ext';
                      bundledImages[photoFileName] = bytes;
                      itemMap['image_path'] = photoFileName;
                      totalPhotos++;
                    }
                  } catch (_) {}
                }
              }

              final meas = itemMap['measurements'] as Map<String, dynamic>? ?? {};
              totalMeasurements += meas.length;

              items[i] = itemMap;
            }
          }

          // Also check and bundle top-level order image_path (Cloudinary photos)
          final topImgStr = (orderData['image_path'] ?? o['image_path'] ?? '').toString().trim();
          if (topImgStr.isNotEmpty) {
            final List<String> updatedTopPaths = [];
            final parts = topImgStr.split(',');
            final orderId = orderData['id'] ?? o['id'];

            for (int pIdx = 0; pIdx < parts.length; pIdx++) {
              final rawPart = parts[pIdx].trim();
              if (rawPart.isEmpty) continue;

              if (rawPart.startsWith('data:image')) {
                try {
                  final b64 = rawPart.split(',').last;
                  final bytes = base64Decode(b64);
                  final photoFileName = 'photos/order_${orderId}_top_$pIdx.jpg';
                  bundledImages[photoFileName] = bytes;
                  updatedTopPaths.add(photoFileName);
                  totalPhotos++;
                } catch (_) {}
              } else if (rawPart.startsWith('http://') || rawPart.startsWith('https://')) {
                final ext = _getExtension(rawPart);
                final photoFileName = 'photos/order_${orderId}_top_$pIdx$ext';
                remoteImageEntries.add(_ImageEntry(
                  url: rawPart,
                  zipPath: photoFileName,
                  orderId: orderId,
                  itemIndex: -1,
                ));
                updatedTopPaths.add(photoFileName);
                totalPhotos++;
              } else {
                try {
                  final bytes = await readLocalPhotoFile(rawPart);
                  if (bytes != null && bytes.isNotEmpty) {
                    final ext = _getExtension(rawPart);
                    final photoFileName = 'photos/order_${orderId}_top_$pIdx$ext';
                    bundledImages[photoFileName] = bytes;
                    updatedTopPaths.add(photoFileName);
                    totalPhotos++;
                  }
                } catch (_) {}
              }
            }

            if (updatedTopPaths.isNotEmpty) {
              orderData['image_path_original'] = topImgStr;
              orderData['image_path'] = updatedTopPaths.join(',');
              if (items.isNotEmpty && items[0] is Map) {
                final itMap = Map<String, dynamic>.from(items[0]);
                if ((itMap['image_path'] ?? '').toString().isEmpty) {
                  itMap['image_path'] = updatedTopPaths.first;
                  items[0] = itMap;
                }
              }
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

    onProgress?.call(
      'Data prepared. Found $totalPhotos photos (${remoteImageEntries.length} to download)...',
      0.1,
    );

    // 3. Download remote images (e.g. from Cloudinary)
    int downloadedCount = 0;
    int failedCount = 0;

    if (remoteImageEntries.isNotEmpty) {
      for (var entry in remoteImageEntries) {
        try {
          final response = await http.get(Uri.parse(entry.url)).timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            bundledImages[entry.zipPath] = response.bodyBytes;
          } else {
            failedCount++;
          }
        } catch (_) {
          failedCount++;
        }

        downloadedCount++;
        final progress = 0.1 + (0.7 * downloadedCount / remoteImageEntries.length);
        onProgress?.call(
          'Downloading photo $downloadedCount/${remoteImageEntries.length}...',
          progress,
        );
      }
    }

    onProgress?.call('Creating ZIP archive...', 0.85);

    // 4. Build the JSON backup data
    final Map<String, dynamic> backupData = {
      'app': 'Haroon Tailor',
      'version': '1.0.0',
      'backup_type': 'zip_with_photos',
      'export_timestamp': DateTime.now().toIso8601String(),
      'total_customers': customers?.length ?? 0,
      'total_orders': detailedOrders.length,
      'total_photos': totalPhotos,
      'bundled_photos': bundledImages.length,
      'failed_photos': failedCount,
      'total_measurements': totalMeasurements,
      'settings': settings ?? {},
      'clothing_types': garmentTypes,
      'message_templates': messageTemplates,
      'default_rates': defaultRates,
      'customers': customers ?? [],
      'orders': detailedOrders,
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);

    // 5. Create the ZIP archive
    final archive = Archive();

    // Add backup.json
    final jsonBytes = utf8.encode(jsonString);
    archive.addFile(ArchiveFile(
      'backup.json',
      jsonBytes.length,
      jsonBytes,
    ));

    // Add all bundled photos
    for (var entry in bundledImages.entries) {
      archive.addFile(ArchiveFile(
        entry.key,
        entry.value.length,
        entry.value,
      ));
    }

    onProgress?.call('Compressing ZIP file...', 0.95);

    // 6. Encode to ZIP bytes
    final zipBytes = ZipEncoder().encode(archive);

    final size = _formatBytes(zipBytes.length);
    onProgress?.call(
      '✅ ZIP backup ready! $size (${bundledImages.length}/$totalPhotos photos)',
      1.0,
    );
    return Uint8List.fromList(zipBytes);
  }

  /// Restore data from a ZIP backup file.
  /// Extracts backup.json and photos, stores photos locally,
  /// and imports all data into LocalStorageService.
  static Future<Map<String, dynamic>> restoreFromZip({
    required Uint8List zipBytes,
    Function(String status, double progress)? onProgress,
  }) async {
    onProgress?.call('Opening ZIP file...', 0.0);

    try {
      // 1. Decode the ZIP archive
      final archive = ZipDecoder().decodeBytes(zipBytes);

      onProgress?.call('Extracting files...', 0.1);

      // 2. Find and parse backup.json
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

      onProgress?.call('Parsing backup data...', 0.2);

      // 3. Parse the JSON data
      final data = jsonDecode(jsonContent);
      if (data is! Map<String, dynamic>) {
        return {'success': false, 'error': 'Invalid backup JSON format'};
      }

      // 4. Save extracted photos to local storage directory
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
              await savePhotoToLocal(
                filePath: targetPath,
                bytes: entry.value,
              );
              savedPhotos++;
            } catch (_) {}
          }
        } catch (_) {
          // Fallback if local storage directory access fails
        }
      }

      onProgress?.call('Restoring orders & customers...', 0.6);

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
                    // Native mobile/desktop: point directly to saved local file
                    item['image_path'] = '$localPhotosDir/$zipPath';
                  } else {
                    // Web: store clean key, buildSmartImage loads from IndexedDB
                    item['image_path'] = zipPath;
                  }
                }
              }
            }

            // Also restore top-level order image_path
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
          }
        }
      }

      // 6. Restore clothing types if present
      if (data['clothing_types'] is List) {
        await LocalStorageService.saveGarmentTypes(
          List<String>.from(data['clothing_types']),
        );
      }

      // 7. Restore message templates if present
      if (data['message_templates'] is Map) {
        await LocalStorageService.saveMessageTemplates(
          Map<String, String>.from(data['message_templates']),
        );
      }

      // 8. Restore default rates if present
      if (data['default_rates'] is Map) {
        final rates = (data['default_rates'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
        await LocalStorageService.saveDefaultRates(rates);
      }

      // 9. Import orders & customers via existing master backup importer
      onProgress?.call('Importing all data into app...', 0.7);
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

  /// Runs auto-backup if enabled and interval has passed (e.g. daily)
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
      final dateStr = DateTime.now().toIso8601String().split('T').first;
      final fileName = 'HaroonTailor_AutoBackup_$dateStr.zip';

      await FileHelper.downloadBackupZip(
        zipBytes: zipBytes,
        fileName: fileName,
      );

      await LocalStorageService.recordAutoBackupTime();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _ImageEntry {
  final String url;
  final String zipPath;
  final dynamic orderId;
  final int itemIndex;

  _ImageEntry({
    required this.url,
    required this.zipPath,
    required this.orderId,
    required this.itemIndex,
  });
}
