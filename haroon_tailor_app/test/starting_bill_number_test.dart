import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:haroon_tailor_app/services/local_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LocalStorageService.clearAll();
  });

  test('Default starting bill number starts at 1 when no orders exist', () async {
    final nextBill = await LocalStorageService.getNextBillNumber();
    expect(nextBill, equals('Bill-000001'));
  });

  test('Setting custom starting bill number to 1001 generates Bill-001001', () async {
    await LocalStorageService.saveCustomStartingBillNumber(1001);
    final saved = await LocalStorageService.getCustomStartingBillNumber();
    expect(saved, equals(1001));

    final nextBill = await LocalStorageService.getNextBillNumber();
    expect(nextBill, equals('Bill-001001'));
  });

  test('Orders created advance the bill number sequentially from custom starting number', () async {
    await LocalStorageService.saveCustomStartingBillNumber(500);

    // Create first order
    final order1 = await LocalStorageService.saveOrderOffline({
      'customer_name': 'Test Customer',
      'items': [],
      'total_amount': 1000.0,
    });
    expect(order1['order_number'], equals('Bill-000500'));

    // Check next bill number preview
    final nextBill2 = await LocalStorageService.getNextBillNumber();
    expect(nextBill2, equals('Bill-000501'));

    // Create second order
    final order2 = await LocalStorageService.saveOrderOffline({
      'customer_name': 'Second Customer',
      'items': [],
      'total_amount': 500.0,
    });
    expect(order2['order_number'], equals('Bill-000501'));

    // Check next bill number preview
    final nextBill3 = await LocalStorageService.getNextBillNumber();
    expect(nextBill3, equals('Bill-000502'));
  });

  test('Resetting custom starting bill number restores standard max+1 numbering', () async {
    await LocalStorageService.saveCustomStartingBillNumber(100);
    await LocalStorageService.saveOrderOffline({
      'customer_name': 'Test',
      'items': [],
    });

    // Reset starting bill number to null
    await LocalStorageService.saveCustomStartingBillNumber(null);
    final saved = await LocalStorageService.getCustomStartingBillNumber();
    expect(saved, isNull);

    // Next bill should naturally be Bill-000101 (max 100 + 1)
    final nextBill = await LocalStorageService.getNextBillNumber();
    expect(nextBill, equals('Bill-000101'));
  });

  test('Thermal paper size defaults to 80mm and can be toggled', () async {
    // Default should be 80mm
    final defaultSize = await LocalStorageService.getThermalPaperSize();
    expect(defaultSize, equals('80mm'));

    // Change to 58mm
    await LocalStorageService.saveThermalPaperSize('58mm');
    final updated = await LocalStorageService.getThermalPaperSize();
    expect(updated, equals('58mm'));

    // Switch back to 80mm
    await LocalStorageService.saveThermalPaperSize('80mm');
    final restored = await LocalStorageService.getThermalPaperSize();
    expect(restored, equals('80mm'));
  });

  test('Large collections (orders, customers) do not pollute SharedPreferences', () async {
    final prefs = await SharedPreferences.getInstance();

    await LocalStorageService.saveOrders([
      {'id': 1, 'order_number': 'Bill-000001', 'total_amount': 500}
    ]);
    await LocalStorageService.saveCustomers([
      {'id': 1, 'name': 'Haroon Customer', 'mobile': '9881432195'}
    ]);

    // SharedPreferences should NOT contain the massive cache keys
    expect(prefs.containsKey('ht_cache_orders'), isFalse);
    expect(prefs.containsKey('ht_cache_customers'), isFalse);

    // But data is still fully accessible via LocalStorageService
    final orders = await LocalStorageService.getCachedOrders();
    expect(orders, isNotNull);
    expect(orders!.length, equals(1));
    expect(orders[0]['order_number'], equals('Bill-000001'));

    final customers = await LocalStorageService.getCachedCustomers();
    expect(customers, isNotNull);
    expect(customers!.length, equals(1));
    expect(customers[0]['name'], equals('Haroon Customer'));
  });

  test('Custom clothing rates are saved and loaded correctly', () async {
    final defaultRates = await LocalStorageService.getDefaultRates();
    expect(defaultRates['Shirt'], equals(400.0));
    expect(defaultRates['Pant'], equals(500.0));

    // Update rates in settings
    final updated = Map<String, double>.from(defaultRates);
    updated['Shirt'] = 350.0;
    updated['Pant'] = 450.0;
    updated['Sadri'] = 900.0;
    await LocalStorageService.saveDefaultRates(updated);

    final reloaded = await LocalStorageService.getDefaultRates();
    expect(reloaded['Shirt'], equals(350.0));
    expect(reloaded['Pant'], equals(450.0));
    expect(reloaded['Sadri'], equals(900.0));
  });
}

