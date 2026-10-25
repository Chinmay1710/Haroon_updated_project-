import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haroon_tailor_app/services/zip_backup_service.dart';
import 'package:haroon_tailor_app/services/local_storage_service.dart';
import 'package:haroon_tailor_app/utils/file_download_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Smart Incremental Backup & Recovery Tests', () {
    test('1. Canonical ZIP path deduplicates identical URLs and formats correctly', () {
      const url1 = 'https://res.cloudinary.com/t4m27rpl/image/upload/v1792774838/haroon_tailor/items/rb9knj6te8e1hotmikqg.jpg';
      const url2 = 'https://res.cloudinary.com/t4m27rpl/image/upload/v1792774838/haroon_tailor/items/rb9knj6te8e1hotmikqg.jpg';
      const url3 = 'https://res.cloudinary.com/t4m27rpl/image/upload/v1792774622/haroon_tailor/items/qimc5yzkov3a9h6lpgbs.jpg';

      final path1 = ZipBackupService.getCanonicalZipPath(url1);
      final path2 = ZipBackupService.getCanonicalZipPath(url2);
      final path3 = ZipBackupService.getCanonicalZipPath(url3);

      expect(path1, equals(path2), reason: 'Identical URLs must yield the exact same canonical path');
      expect(path1, isNot(equals(path3)), reason: 'Different URLs must yield different canonical paths');
      expect(path1.startsWith('photos/'), isTrue);
      expect(path1.contains('rb9knj6te8e1hotmikqg'), isTrue);

      // Relative path handling
      expect(ZipBackupService.getCanonicalZipPath('photos/existing.png'), equals('photos/existing.png'));
    });

    test('2. Atomic saveStableBackupZipPlatform creates stable file and preserves valid file on corrupt error', () async {
      final tempDir = await Directory.systemTemp.createTemp('backup_test_');

      // Create a valid test ZIP archive
      final validArchive = Archive();
      final validJsonBytes = utf8.encode(jsonEncode({'app': 'Haroon Tailor', 'version': '1.1.0'}));
      validArchive.addFile(ArchiveFile('backup.json', validJsonBytes.length, validJsonBytes));
      final validZipBytes = Uint8List.fromList(ZipEncoder().encode(validArchive));

      // 1. Initial valid write
      final savedPath = await saveStableBackupZipPlatform(
        zipBytes: validZipBytes,
        fileName: 'HaroonTailor_Backup.zip',
      );
      expect(savedPath, isNotNull);
      final file = File(savedPath!);
      expect(await file.exists(), isTrue);
      final initialSize = await file.length();

      // 2. Attempt to save corrupted bytes
      final corruptBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () async => await saveStableBackupZipPlatform(
          zipBytes: corruptBytes,
          fileName: 'HaroonTailor_Backup.zip',
        ),
        throwsA(isA<Exception>()),
      );

      // 3. Verify original valid backup is preserved intact
      expect(await file.exists(), isTrue);
      expect(await file.length(), equals(initialSize));

      // Cleanup
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('3. Full Settings Backup and Restore Verification', () async {
      // 1. Configure test settings in LocalStorageService
      await LocalStorageService.saveShopSettings({
        'shop_name': 'Haroon Master Tailors',
        'owner_name': 'Haroon Bhai',
        'phone': '9876543210',
        'address': 'Main Market, Mumbai',
      });
      await LocalStorageService.saveGarmentTypes(['Kurta', 'Pajama', 'Sherwani', 'Jacket']);
      await LocalStorageService.saveMessageTemplates({'ready': 'Aapke kapde tayyar hain.'});
      await LocalStorageService.saveDefaultRates({'Kurta': 500.0, 'Sherwani': 3500.0});
      await LocalStorageService.saveAppTheme('dark');
      await LocalStorageService.saveAppLanguage('hi');
      await LocalStorageService.saveMeasurementUnit('Inches (in)');
      await LocalStorageService.saveDefaultDeliveryDays(5);
      await LocalStorageService.saveNotesSuggestions(['Loose fitting', 'Double pocket']);
      await LocalStorageService.setAutoBackupEnabled(true);
      await LocalStorageService.setAutoBackupFrequency('weekly');

      // 2. Add an order and customer
      final customer = {'id': 101, 'name': 'Ahmed Khan', 'mobile': '9998887770'};
      final order = {
        'id': 501,
        'order_number': 'ORD-501',
        'customer_id': 101,
        'customer_name': 'Ahmed Khan',
        'status': 'NEW',
        'total_amount': 2000.0,
        'advance_amount': 500.0,
        'remaining_amount': 1500.0,
        'items': [
          {
            'clothing_type': 'Kurta',
            'quantity': 2,
            'image_path': 'https://res.cloudinary.com/test/item1.jpg',
            'measurements': {'length': '42', 'chest': '38'},
          }
        ],
        'image_path': 'https://res.cloudinary.com/test/item1.jpg',
        'cloth_photos': ['https://res.cloudinary.com/test/item1.jpg'],
      };

      await LocalStorageService.saveCustomers([customer]);
      await LocalStorageService.saveOrders([order]);
      await LocalStorageService.saveOrderDetails(501, order);

      // 3. Create ZIP backup
      final zipBytes = await ZipBackupService.createZipBackup();
      expect(zipBytes, isNotEmpty);

      // 4. Verify contents of generated backup.json
      final decodedArchive = ZipDecoder().decodeBytes(zipBytes, verify: true);
      final jsonFile = decodedArchive.files.firstWhere((f) => f.name == 'backup.json');
      final backupData = jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;

      // Check settings exist in backup
      expect(backupData['app_theme'], equals('dark'));
      expect(backupData['app_language'], equals('hi'));
      expect(backupData['default_delivery_days'], equals(5));
      expect(backupData['clothing_types'], contains('Sherwani'));
      expect(backupData['default_rates']['Sherwani'], equals(3500.0));
      expect(backupData['settings']['shop_name'], equals('Haroon Master Tailors'));

      // Check deduplication in backupData: 3 raw references -> 1 unique photo
      expect(backupData['total_unique_photos'], equals(1));

      // 5. Simulate restoring on a brand new blank app
      await LocalStorageService.clearAll();
      expect(await LocalStorageService.getCachedOrders(), isEmpty);

      // Restore from the generated ZIP
      final restoreRes = await ZipBackupService.restoreFromZip(zipBytes: zipBytes);
      expect(restoreRes['success'], isTrue);

      // 6. Verify restored settings in fresh app
      final restoredTheme = await LocalStorageService.getAppTheme();
      final restoredLang = await LocalStorageService.getAppLanguage();
      final restoredDays = await LocalStorageService.getDefaultDeliveryDays();
      final restoredRates = await LocalStorageService.getDefaultRates();
      final restoredTypes = await LocalStorageService.getGarmentTypes();
      final restoredShop = await LocalStorageService.getCachedShopSettings();
      final restoredOrders = await LocalStorageService.getCachedOrders();

      expect(restoredTheme, equals('dark'));
      expect(restoredLang, equals('hi'));
      expect(restoredDays, equals(5));
      expect(restoredRates['Sherwani'], equals(3500.0));
      expect(restoredTypes, contains('Sherwani'));
      expect(restoredShop?['shop_name'], equals('Haroon Master Tailors'));
      expect(restoredOrders, isNotNull);
      expect(restoredOrders!.length, equals(1));
    });

    test('4. Incremental Photo Reuse from Existing Backup ZIP', () async {
      // Create a simulated previous backup ZIP with a photo 'photos/cached_photo_1.jpg'
      final prevArchive = Archive();
      final prevJson = utf8.encode(jsonEncode({'app': 'Haroon Tailor', 'version': '1.0.0'}));
      prevArchive.addFile(ArchiveFile('backup.json', prevJson.length, prevJson));
      final fakePhotoBytes = Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]);
      prevArchive.addFile(ArchiveFile('photos/cached_photo_1.jpg', fakePhotoBytes.length, fakePhotoBytes));
      final prevZipBytes = Uint8List.fromList(ZipEncoder().encode(prevArchive));

      // Save as existing stable backup
      await saveStableBackupZipPlatform(zipBytes: prevZipBytes, fileName: 'HaroonTailor_Backup.zip');

      // Now create an order referencing that exact same photo relative path
      final order = {
        'id': 601,
        'order_number': 'ORD-601',
        'customer_id': 102,
        'customer_name': 'Zaid',
        'status': 'NEW',
        'items': [
          {
            'clothing_type': 'Pant',
            'quantity': 1,
            'image_path': 'photos/cached_photo_1.jpg',
          }
        ],
        'image_path': 'photos/cached_photo_1.jpg',
      };
      await LocalStorageService.saveOrders([order]);
      await LocalStorageService.saveOrderDetails(601, order);

      // Create new backup
      final newZipBytes = await ZipBackupService.createZipBackup();
      final newArchive = ZipDecoder().decodeBytes(newZipBytes, verify: true);

      // Verify the photo was extracted from the previous ZIP into the new backup without needing network
      final bundledPhoto = newArchive.files.firstWhere((f) => f.name == 'photos/cached_photo_1.jpg');
      expect(bundledPhoto.content as List<int>, equals(fakePhotoBytes));
    });

    test('5. Start Fresh Offline App resets all values to 00 and enables offline mode', () async {
      // Seed some dummy orders and customers
      await LocalStorageService.saveOrders([
        {'id': 1, 'order_number': 'ORD-001', 'total_amount': 500}
      ]);
      await LocalStorageService.saveCustomers([
        {'id': 1, 'name': 'Test Cust', 'mobile': '9999999999'}
      ]);

      expect((await LocalStorageService.getCachedOrders())?.length, equals(1));
      expect((await LocalStorageService.getCachedCustomers())?.length, equals(1));

      // Trigger Start Fresh Offline App (Clear All Data)
      await LocalStorageService.clearAll(enableOfflineMode: true);

      // Verify all cached datasets are now empty
      final freshOrders = await LocalStorageService.getCachedOrders();
      final freshCustomers = await LocalStorageService.getCachedCustomers();
      final freshStats = await LocalStorageService.getCachedDashboardStats();
      final isOffline = await LocalStorageService.isOfflineMode();

      expect(freshOrders, isNotNull);
      expect(freshOrders, isEmpty);
      expect(freshCustomers, isNotNull);
      expect(freshCustomers, isEmpty);
      expect(isOffline, isTrue);

      expect(freshStats, isNotNull);
      expect(freshStats!['total_orders'], equals(0));
      expect(freshStats['orders_today'], equals(0));
      expect(freshStats['deliveries_today'], equals(0));
      expect(freshStats['pending_payments'], equals(0));
      expect(freshStats['total_revenue'], equals(0));
      expect(freshStats['recent_orders'], isEmpty);
    });
  });
}
