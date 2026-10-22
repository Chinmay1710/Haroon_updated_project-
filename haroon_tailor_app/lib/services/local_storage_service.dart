import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalStorageService {
  static const String _keyOrders = 'ht_cache_orders';
  static const String _keyCustomers = 'ht_cache_customers';
  static const String _keyDashboard = 'ht_cache_dashboard';
  static const String _keyDeliveries = 'ht_cache_deliveries';
  static const String _keyPendingOrders = 'ht_cache_pending_orders';
  static const String _keySettings = 'ht_cache_settings';
  static const String _keyLastSync = 'ht_cache_last_sync';

  // -------------------------------------------------------------
  // ORDERS CACHE
  // -------------------------------------------------------------
  static Future<void> saveOrders(List<dynamic> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyOrders, jsonEncode(orders));
      await _recordSyncTime();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyOrders);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // SINGLE ORDER DETAILS CACHE
  // -------------------------------------------------------------
  static Future<void> saveOrderDetails(int orderId, Map<String, dynamic> order) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_cache_order_$orderId', jsonEncode(order));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedOrderDetails(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ht_cache_order_$orderId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // CUSTOMERS CACHE
  // -------------------------------------------------------------
  static Future<void> saveCustomers(List<dynamic> customers) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonEncode(customers));
      await _recordSyncTime();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedCustomers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCustomers);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // CUSTOMER DETAILS & MEASUREMENTS CACHE
  // -------------------------------------------------------------
  static Future<void> saveCustomerDetails(int customerId, Map<String, dynamic> details) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_cache_customer_$customerId', jsonEncode(details));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedCustomerDetails(int customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ht_cache_customer_$customerId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveMeasurements(int customerId, List<dynamic> measurements) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_cache_measurements_$customerId', jsonEncode(measurements));
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedMeasurements(int customerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ht_cache_measurements_$customerId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // DASHBOARD STATS CACHE
  // -------------------------------------------------------------
  static Future<void> saveDashboardStats(Map<String, dynamic> stats) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDashboard, jsonEncode(stats));
      await _recordSyncTime();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedDashboardStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyDashboard);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // DELIVERIES CACHE
  // -------------------------------------------------------------
  static Future<void> saveDeliveries(Map<String, dynamic> deliveries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDeliveries, jsonEncode(deliveries));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedDeliveries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyDeliveries);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // PENDING PAYMENTS CACHE
  // -------------------------------------------------------------
  static Future<void> savePendingOrders(List<dynamic> orders) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPendingOrders, jsonEncode(orders));
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedPendingOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyPendingOrders);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // SHOP SETTINGS CACHE
  // -------------------------------------------------------------
  static Future<void> saveShopSettings(Map<String, dynamic> settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySettings, jsonEncode(settings));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedShopSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySettings);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // SYNC TIMESTAMP
  // -------------------------------------------------------------
  static Future<void> _recordSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSync, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyLastSync);
      if (raw != null && raw.isNotEmpty) {
        return DateTime.tryParse(raw);
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // CLOTHING / GARMENT TYPES
  // -------------------------------------------------------------
  static const String _keyGarmentTypes = 'ht_garment_types';
  static const List<String> defaultGarmentTypes = [
    'Shirt',
    'Pant',
    'Kurta',
    'Pajama',
    'Safari Suit',
    'Blazer / Coat',
    'Sherwani',
    'Sadri / Waistcoat',
    'Custom Item',
  ];

  static Future<List<String>> getGarmentTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_keyGarmentTypes);
      if (list != null && list.isNotEmpty) {
        return list;
      }
    } catch (_) {}
    return List<String>.from(defaultGarmentTypes);
  }

  static Future<void> saveGarmentTypes(List<String> types) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyGarmentTypes, types);
    } catch (_) {}
  }

  static Future<bool> addGarmentType(String type) async {
    final clean = type.trim();
    if (clean.isEmpty) return false;
    final current = await getGarmentTypes();
    if (current.any((t) => t.toLowerCase() == clean.toLowerCase())) {
      return false; // Already exists
    }
    current.add(clean);
    await saveGarmentTypes(current);
    return true;
  }

  static Future<bool> removeGarmentType(String type) async {
    final current = await getGarmentTypes();
    final beforeLen = current.length;
    current.removeWhere((t) => t.toLowerCase() == type.trim().toLowerCase());
    if (current.length != beforeLen) {
      await saveGarmentTypes(current);
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------
  // MESSAGE TEMPLATES (WHATSAPP & SMS)
  // -------------------------------------------------------------
  static const String _keyMsgTemplates = 'ht_msg_templates';

  static Map<String, String> get defaultMessageTemplates => {
    'new_order':
        'Namaste {customer_name}, aapka order #{order_number} ({garments}) darj ho gaya hai. '
        'Total: Rs.{total_amount}, Advance: Rs.{advance_amount}, Baaki: Rs.{balance_amount}. '
        'Delivery Date: {delivery_date}. Dhanyawad, {shop_name} ({shop_phone}).',
    'order_ready':
        'Namaste {customer_name}, aapka kapda order #{order_number} sil kar taiyar hai! '
        'Kripya dukaan par aakar trial ya delivery le lein. '
        'Pending Balance: Rs.{balance_amount}. - {shop_name}.',
    'delivered':
        'Namaste {customer_name}, aapka order #{order_number} successfully deliver ho gaya hai. '
        'Haroon Tailor ke saath judne ke liye dhanyawad! Agli bar fir sewa ka mauka dein.',
    'payment_reminder':
        'Namaste {customer_name}, aapke order #{order_number} ka baaki hisab Rs.{balance_amount} pending hai. '
        'Kripya jald se jald bhugtan karein. Dhanyawad, {shop_name}.',
  };

  static Future<Map<String, String>> getMessageTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyMsgTemplates);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final res = Map<String, String>.from(defaultMessageTemplates);
          decoded.forEach((k, v) {
            if (v != null) res[k.toString()] = v.toString();
          });
          return res;
        }
      }
    } catch (_) {}
    return Map<String, String>.from(defaultMessageTemplates);
  }

  static Future<void> saveMessageTemplates(Map<String, String> templates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMsgTemplates, jsonEncode(templates));
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // THEME & LANGUAGE
  // -------------------------------------------------------------
  static const String _keyAppTheme = 'ht_app_theme'; // 'system', 'light', 'dark'
  static const String _keyAppLang = 'ht_app_lang';   // 'en', 'hi'

  static Future<String> getAppTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAppTheme) ?? 'system';
    } catch (_) {
      return 'system';
    }
  }

  static Future<void> saveAppTheme(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAppTheme, mode);
    } catch (_) {}
  }

  static Future<String> getAppLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAppLang) ?? 'en';
    } catch (_) {
      return 'en';
    }
  }

  static Future<void> saveAppLanguage(String lang) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAppLang, lang);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // DEFAULT STITCHING RATES & PREFERENCES
  // -------------------------------------------------------------
  static const String _keyDefaultRates = 'ht_default_rates';
  static const String _keyDeliveryGraceDays = 'ht_default_delivery_days';
  static const String _keyMeasurementUnit = 'ht_default_unit';

  static Future<Map<String, double>> getDefaultRates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyDefaultRates);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
        }
      }
    } catch (_) {}
    return {
      'Shirt': 400.0,
      'Pant': 500.0,
      'Kurta': 450.0,
      'Pajama': 250.0,
      'Safari Suit': 1200.0,
      'Blazer / Coat': 2500.0,
      'Sherwani': 3500.0,
      'Sadri / Waistcoat': 800.0,
    };
  }

  static Future<void> saveDefaultRates(Map<String, double> rates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultRates, jsonEncode(rates));
    } catch (_) {}
  }

  static Future<int> getDefaultDeliveryDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyDeliveryGraceDays) ?? 7;
    } catch (_) {
      return 7;
    }
  }

  static Future<void> saveDefaultDeliveryDays(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyDeliveryGraceDays, days);
    } catch (_) {}
  }

  static Future<String> getMeasurementUnit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyMeasurementUnit) ?? 'Inches (in)';
    } catch (_) {
      return 'Inches (in)';
    }
  }

  static Future<void> saveMeasurementUnit(String unit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMeasurementUnit, unit);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // LOCAL BACKUP EXPORT & IMPORT (OFFLINE RESTORE)
  // -------------------------------------------------------------
  static Future<String> exportLocalBackupJson() async {
    final Map<String, dynamic> backupData = {
      'app': 'Haroon Tailor',
      'version': '1.0.0',
      'export_timestamp': DateTime.now().toIso8601String(),
      'clothing_types': await getGarmentTypes(),
      'message_templates': await getMessageTemplates(),
      'default_rates': await getDefaultRates(),
      'shop_settings': await getCachedShopSettings(),
      'orders_cache': await getCachedOrders(),
      'customers_cache': await getCachedCustomers(),
      'deliveries_cache': await getCachedDeliveries(),
      'pending_orders_cache': await getCachedPendingOrders(),
    };
    return const JsonEncoder.withIndent('  ').convert(backupData);
  }

  static Future<bool> importLocalBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return false;

      if (decoded['clothing_types'] is List) {
        final list = List<String>.from(decoded['clothing_types']);
        await saveGarmentTypes(list);
      }
      if (decoded['message_templates'] is Map) {
        final map = Map<String, String>.from(decoded['message_templates']);
        await saveMessageTemplates(map);
      }
      if (decoded['default_rates'] is Map) {
        final rates = (decoded['default_rates'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        );
        await saveDefaultRates(rates);
      }
      if (decoded['shop_settings'] is Map) {
        await saveShopSettings(Map<String, dynamic>.from(decoded['shop_settings']));
      }
      if (decoded['orders_cache'] is List) {
        await saveOrders(decoded['orders_cache']);
      }
      if (decoded['customers_cache'] is List) {
        await saveCustomers(decoded['customers_cache']);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------
  // CLEAR CACHE
  // -------------------------------------------------------------
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}

