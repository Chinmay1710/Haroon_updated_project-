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
  // CLEAR CACHE
  // -------------------------------------------------------------
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (_) {}
  }
}
