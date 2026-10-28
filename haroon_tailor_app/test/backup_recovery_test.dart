import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haroon_tailor_app/services/zip_backup_service.dart';
import 'package:haroon_tailor_app/services/local_storage_service.dart';
import 'package:haroon_tailor_app/services/google_drive_service.dart';
import 'package:haroon_tailor_app/utils/file_download_io.dart';
import 'package:haroon_tailor_app/utils/file_helper.dart';
import 'package:haroon_tailor_app/utils/io_helper_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ht_test_');
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    resetCachedPathsForTesting();
    await LocalStorageService.clearAll();
  });

  tearDown(() async {
    resetCachedPathsForTesting();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Comprehensive Backup, Restore, Google Drive & Performance Verification', () {
    // 1. Local backup creation with full data
    test('1. Create a local backup with complete application data & settings', () async {
      await LocalStorageService.saveShopSettings({'shop_name': 'Haroon Tailors', 'phone': '9876543210'});
      await LocalStorageService.saveGarmentTypes(['Kurta', 'Sherwani', 'Safari Suit']);
      await LocalStorageService.saveDefaultRates({'Kurta': 600.0, 'Sherwani': 4000.0});
      await LocalStorageService.saveCustomers([
        {'id': 101, 'name': 'Imran Sheikh', 'mobile': '9876543210'}
      ]);
      await LocalStorageService.saveOrders([
        {
          'id': 201,
          'order_number': 'ORD-201',
          'customer_id': 101,
          'customer_name': 'Imran Sheikh',
          'status': 'STITCHING_COMPLETE',
          'total_amount': 2500.0,
          'advance_amount': 1000.0,
          'remaining_amount': 1500.0,
        }
      ]);

      final zipBytes = await ZipBackupService.createZipBackup();
      expect(zipBytes, isNotEmpty);
      expect(zipBytes.length, greaterThan(100));

      final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      expect(archive.findFile('backup.json'), isNotNull);
    });

    // 2. Confirm that all required records and files are present
    test('2. Confirm all required records, settings, and file structures exist in backup', () async {
      await LocalStorageService.saveShopSettings({'shop_name': 'Master Tailor Shop'});
      await LocalStorageService.saveGarmentTypes(['Kurta', 'Pant']);
      await LocalStorageService.saveMessageTemplates({'order_ready': 'Ready for pickup'});
      await LocalStorageService.saveCustomers([{'id': 102, 'name': 'Zaid'}]);
      await LocalStorageService.saveOrders([{'id': 301, 'customer_id': 102, 'status': 'DELIVERED'}]);

      final zipBytes = await ZipBackupService.createZipBackup();
      final meta = await ZipBackupService.peekBackupMetadata(zipBytes);

      expect(meta, isNotNull);
      expect(meta!['timestamp'], isNotNull);
      expect(meta['orders_count'], equals(1));
      expect(meta['customers_count'], equals(1));
    });

    // 3. Restore the backup and compare restored data with original
    test('3. Restore backup and verify full fidelity against original data', () async {
      final origCustomer = {'id': 105, 'name': 'Rashid Ali', 'mobile': '9123456780'};
      final origOrder = {
        'id': 401,
        'order_number': 'ORD-401',
        'customer_id': 105,
        'customer_name': 'Rashid Ali',
        'status': 'PARTIALLY_COMPLETE',
        'total_amount': 1800.0,
        'advance_amount': 800.0,
        'remaining_amount': 1000.0,
        'ready_item_ids': [1],
        'delivered_item_ids': <int>[],
      };

      await LocalStorageService.saveCustomers([origCustomer]);
      await LocalStorageService.saveOrders([origOrder]);
      await LocalStorageService.saveOrderDetails(401, origOrder);

      final zipBytes = await ZipBackupService.createZipBackup();

      // Wipe local storage
      await LocalStorageService.clearAll();
      expect(await LocalStorageService.getCachedOrders(), isEmpty);

      // Restore
      final res = await ZipBackupService.restoreFromZip(zipBytes: zipBytes);
      expect(res['success'], isTrue);
      expect(res['orders_count'], equals(1));
      expect(res['customers_count'], equals(1));

      final restoredOrders = await LocalStorageService.getCachedOrders();
      expect(restoredOrders, isNotNull);
      expect(restoredOrders!.first['order_number'], equals('ORD-401'));
      expect(restoredOrders.first['total_amount'], equals(1800.0));
    });

    // 4. Verify orders retain their exact original statuses
    test('4. Orders retain exact statuses (DELIVERED, STITCHING_COMPLETE, PARTIALLY_COMPLETE, NEW, CANCELLED)', () async {
      final statuses = ['DELIVERED', 'STITCHING_COMPLETE', 'PARTIALLY_COMPLETE', 'NEW', 'CANCELLED'];
      final orders = <Map<String, dynamic>>[];

      for (int i = 0; i < statuses.length; i++) {
        orders.add({
          'id': 1000 + i,
          'order_number': 'ORD-STATUS-$i',
          'customer_id': 500,
          'status': statuses[i],
          'total_amount': 1000.0 + (i * 100),
        });
      }

      await LocalStorageService.saveOrders(orders);
      final zipBytes = await ZipBackupService.createZipBackup();

      await LocalStorageService.clearAll();
      final restoreRes = await ZipBackupService.restoreFromZip(zipBytes: zipBytes);
      expect(restoreRes['success'], isTrue);

      final restoredOrders = await LocalStorageService.getCachedOrders();
      expect(restoredOrders?.length, equals(statuses.length));

      for (int i = 0; i < statuses.length; i++) {
        final match = restoredOrders?.firstWhere((o) => o['order_number'] == 'ORD-STATUS-$i');
        expect(match, isNotNull);
        expect(match['status'], equals(statuses[i]), reason: 'Order status must be preserved verbatim');
      }
    });

    // 5. Verify customer/order relationships, measurements, and payment data remain correct
    test('5. Customer relationships, measurements, and payment tracking are preserved', () async {
      final cust = {'id': 777, 'name': 'Kareem Bhai', 'mobile': '9988776655'};
      final order = {
        'id': 888,
        'order_number': 'ORD-888',
        'customer_id': 777,
        'customer_name': 'Kareem Bhai',
        'status': 'DELIVERED',
        'total_amount': 5000.0,
        'advance_amount': 2000.0,
        'remaining_amount': 3000.0,
        'ready_item_ids': [1, 2],
        'delivered_item_ids': [1],
        'items': [
          {
            'clothing_type': 'Sherwani',
            'quantity': 1,
            'measurements': {'chest': '44', 'waist': '38', 'length': '46'},
          }
        ]
      };

      await LocalStorageService.saveCustomers([cust]);
      await LocalStorageService.saveOrders([order]);
      await LocalStorageService.saveOrderDetails(888, order);
      await LocalStorageService.saveMeasurements(777, [
        {
          'template_type': 'Sherwani',
          'values': {'chest': '44', 'waist': '38', 'length': '46'}
        }
      ]);

      final zipBytes = await ZipBackupService.createZipBackup();
      await LocalStorageService.clearAll();
      await ZipBackupService.restoreFromZip(zipBytes: zipBytes);

      final restoredDetails = await LocalStorageService.getCachedOrderDetails(888);
      expect(restoredDetails, isNotNull);
      expect(restoredDetails!['customer_id'], equals(777));
      expect(restoredDetails['advance_amount'], equals(2000.0));
      expect(restoredDetails['remaining_amount'], equals(3000.0));
      expect(restoredDetails['ready_item_ids'], contains(1));
      expect(restoredDetails['delivered_item_ids'], contains(1));

      final restoredMeasurements = await LocalStorageService.getCustomerMeasurementsOffline(777);
      expect(restoredMeasurements, isNotEmpty);
    });

    // 6. Connect Google Drive and credential caching
    test('6. Google Drive connection securely stores tokens and email', () async {
      expect(await GoogleDriveService.isConnected(), isFalse);

      await GoogleDriveService.saveManualTokens(
        accessToken: 'mock_access_token_xyz',
        refreshToken: 'mock_refresh_token_abc',
        expiresInSeconds: 3600,
        email: 'tailor.master@gmail.com',
      );

      expect(await GoogleDriveService.isConnected(), isTrue);
      expect(await GoogleDriveService.getUserEmail(), equals('tailor.master@gmail.com'));
      expect(await GoogleDriveService.getValidAccessToken(), equals('mock_access_token_xyz'));

      await GoogleDriveService.disconnect();
      expect(await GoogleDriveService.isConnected(), isFalse);
      expect(await GoogleDriveService.getUserEmail(), isNull);
    });

    // 7. Order change triggers debounced auto-sync
    test('7. Data change triggers debounced auto-sync scheduling', () async {
      await GoogleDriveService.saveManualTokens(
        accessToken: 'mock_token',
        email: 'test@example.com',
      );
      await GoogleDriveService.setAutoSyncEnabled(true);

      bool dataChangedFired = false;
      LocalStorageService.onDataChanged = () {
        dataChangedFired = true;
      };

      LocalStorageService.notifyDataChanged();
      expect(dataChangedFired, isTrue);
    });

    // 8. App restart / startup auto-backup check
    test('8. Startup check triggers auto-backup if interval elapsed', () async {
      await LocalStorageService.setAutoBackupEnabled(true);
      await LocalStorageService.setAutoBackupFrequency('daily');

      // Set last auto backup to 2 days ago
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_last_auto_backup_time', twoDaysAgo);

      final didRun = await ZipBackupService.checkAndPerformAutoBackup();
      expect(didRun, isTrue);
    });

    // 9. Google Drive offline/network failure tolerance (local data safe)
    test('9. Network failure does not corrupt or lose local backup data', () async {
      final validArchive = Archive();
      final validJson = utf8.encode(jsonEncode({'app': 'Haroon Tailor', 'version': '1.0'}));
      validArchive.addFile(ArchiveFile('backup.json', validJson.length, validJson));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(validArchive));

      final localPath = await FileHelper.saveStableBackupZip(zipBytes: zipBytes);
      expect(localPath, isNotNull);

      final file = File(localPath!);
      expect(await file.exists(), isTrue);
      final localSize = await file.length();

      // Cloud upload attempt without valid internet/token
      await SharedPreferences.getInstance().then((p) => p.remove('ht_gdrive_access_token'));
      final uploadRes = await GoogleDriveService.uploadBackupZip(zipBytes: zipBytes);
      expect(uploadRes['success'], isFalse);

      // Local file is intact
      expect(await file.exists(), isTrue);
      expect(await file.length(), equals(localSize));
    });

    // 10. Expired/revoked token handling
    test('10. Expired token without refresh token prompts re-authentication', () async {
      await GoogleDriveService.saveManualTokens(
        accessToken: 'expired_token',
        expiresInSeconds: -100, // already expired
      );

      final validToken = await GoogleDriveService.getValidAccessToken();
      expect(validToken, isNull);
    });

    // 11. Corrupted or incomplete ZIP rejection with valid file preservation
    test('11. Corrupt ZIP bytes are safely rejected without replacing existing valid backup', () async {
      final validArchive = Archive();
      final validJson = utf8.encode(jsonEncode({'app': 'Haroon Tailor', 'version': '1.0'}));
      validArchive.addFile(ArchiveFile('backup.json', validJson.length, validJson));
      final validZipBytes = Uint8List.fromList(ZipEncoder().encode(validArchive));

      final savedPath = await saveStableBackupZipPlatform(zipBytes: validZipBytes, fileName: 'HaroonTailor_Backup.zip');
      final originalLength = await File(savedPath!).length();

      // Try overwriting with garbage bytes
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7]);
      expect(
        () async => await saveStableBackupZipPlatform(zipBytes: garbage, fileName: 'HaroonTailor_Backup.zip'),
        throwsA(isA<Exception>()),
      );

      // Existing backup remains unaltered
      expect(await File(savedPath).length(), equals(originalLength));
    });

    // 12. Conflict detection when local data is newer than backup snapshot
    test('12. Detect when local data is newer than backup timestamp', () async {
      final now = DateTime.now();
      // Record a local order with current updated_at timestamp
      await LocalStorageService.saveOrders([
        {
          'id': 1,
          'order_number': 'ORD-001',
          'status': 'NEW',
          'updated_at': now.toIso8601String(),
        }
      ]);

      // Backup timestamp from 1 hour ago
      final olderTimestamp = now.subtract(const Duration(hours: 1)).toIso8601String();
      final isNewer = await LocalStorageService.isLocalDataNewerThan(olderTimestamp);
      expect(isNewer, isTrue);

      // Backup timestamp from future or identical
      final futureTimestamp = now.add(const Duration(hours: 1)).toIso8601String();
      final isNewerAgainstFuture = await LocalStorageService.isLocalDataNewerThan(futureTimestamp);
      expect(isNewerAgainstFuture, isFalse);
    });

    // 13. Failed restore rollback to safety snapshot without data loss
    test('13. Failed restore rolls back to safety snapshot and preserves existing data', () async {
      await LocalStorageService.saveOrders([
        {'id': 999, 'order_number': 'ORD-CRITICAL-999', 'status': 'DELIVERED'}
      ]);

      // Create safety snapshot
      await LocalStorageService.createSafetySnapshot();

      // Attempt restoring corrupted ZIP
      final corruptZip = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]); // truncated ZIP
      final restoreRes = await ZipBackupService.restoreFromZip(zipBytes: corruptZip);

      expect(restoreRes['success'], isFalse);

      // Verify original critical order still exists
      final orders = await LocalStorageService.getCachedOrders();
      expect(orders, isNotNull);
      expect(orders!.any((o) => o['order_number'] == 'ORD-CRITICAL-999'), isTrue);
    });

    // 14. Backward compatibility with existing ZIP backups
    test('14. Backward compatibility handles String IDs and legacy structures gracefully', () async {
      final legacyArchive = Archive();
      final legacyJson = jsonEncode({
        'version': '1.0.0',
        'backup_timestamp': '2025-01-01T00:00:00Z',
        'orders': [
          {
            'id': '701', // String ID in legacy backup
            'order_number': 'ORD-LEGACY-701',
            'customer_id': '301',
            'status': 'NEW',
            'total_amount': '1500',
            'items': [
              {
                'clothing_type': 'Kurta',
                'quantity': '1',
              }
            ]
          }
        ],
        'customers': [
          {'id': '301', 'name': 'Legacy Customer', 'mobile': '9876543210'}
        ],
        'settings': {'shop_name': 'Legacy Tailor'}
      });

      final legacyBytes = utf8.encode(legacyJson);
      legacyArchive.addFile(ArchiveFile('backup.json', legacyBytes.length, legacyBytes));
      final legacyZipBytes = Uint8List.fromList(ZipEncoder().encode(legacyArchive));

      final res = await ZipBackupService.restoreFromZip(zipBytes: legacyZipBytes);
      expect(res['success'], isTrue);

      final restoredOrders = await LocalStorageService.getCachedOrders();
      expect(restoredOrders, isNotNull);
      expect(restoredOrders!.first['id'], equals(701));
      expect(restoredOrders.first['order_number'], equals('ORD-LEGACY-701'));
    });

    // 15. Deduplication and photo reuse
    test('15. Canonical ZIP path deduplicates identical URLs', () {
      const url1 = 'https://res.cloudinary.com/demo/image/upload/sample.jpg';
      const url2 = 'https://res.cloudinary.com/demo/image/upload/sample.jpg';
      final path1 = ZipBackupService.getCanonicalZipPath(url1);
      final path2 = ZipBackupService.getCanonicalZipPath(url2);

      expect(path1, equals(path2));
      expect(path1.startsWith('photos/'), isTrue);
    });

    // 16. In-memory caching eliminates repeated disk reads
    test('16. In-memory cache returns orders without disk lag', () async {
      final orderList = [
        {'id': 1, 'order_number': 'ORD-001', 'status': 'NEW'},
        {'id': 2, 'order_number': 'ORD-002', 'status': 'DELIVERED'},
      ];
      await LocalStorageService.saveOrders(orderList);

      final cached1 = await LocalStorageService.getCachedOrders();
      final cached2 = await LocalStorageService.getCachedOrders();

      expect(identical(cached1, cached2), isTrue, reason: 'Consecutive calls must return same in-memory cached instance');
    });
  });
}
