import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';

class ApiService {
  static const String baseUrl = 'https://haroon-tailor.onrender.com';
  static const String dispatchEndpoint = '$baseUrl/admin-api/dispatch';

  static Future<dynamic> dispatch(String action, [Map<String, dynamic>? payload]) async {
    try {
      final response = await http.post(
        Uri.parse(dispatchEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'payload': payload ?? {},
        }),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return data['data'];
        } else {
          throw Exception(data['message'] ?? 'Action failed');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  // Dashboard Stats
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final res = await dispatch('get_dashboard_stats');
      final data = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveDashboardStats(data);
      return data;
    } catch (e) {
      final cached = await LocalStorageService.getCachedDashboardStats();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  // Customers
  static Future<List<dynamic>> getCustomers() async {
    try {
      final res = await dispatch('get_customers');
      final list = List<dynamic>.from(res ?? []);
      await LocalStorageService.saveCustomers(list);
      return list;
    } catch (e) {
      final cached = await LocalStorageService.getCachedCustomers();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createCustomer({
    required String name,
    required String mobile,
    String address = '',
    String notes = '',
  }) async {
    final res = await dispatch('create_customer', {
      'name': name,
      'mobile': mobile,
      'address': address,
      'notes': notes,
    });
    final map = Map<String, dynamic>.from(res ?? {});
    // Refresh cached customers in background
    getCustomers().ignore();
    return map;
  }

  // Measurements
  static Future<List<dynamic>> getMeasurementsForCustomer(int customerId) async {
    try {
      final res = await dispatch('get_measurements_for_customer', {'customer_id': customerId});
      final list = List<dynamic>.from(res ?? []);
      await LocalStorageService.saveMeasurements(customerId, list);
      return list;
    } catch (e) {
      final cached = await LocalStorageService.getCachedMeasurements(customerId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  // Orders
  static Future<List<dynamic>> getAllOrders() async {
    try {
      final res = await dispatch('get_all_orders');
      final list = List<dynamic>.from(res ?? []);
      await LocalStorageService.saveOrders(list);
      return list;
    } catch (e) {
      final cached = await LocalStorageService.getCachedOrders();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getOrderDetails(int orderId) async {
    try {
      final res = await dispatch('get_order_details', {'id': orderId});
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveOrderDetails(orderId, map);
      return map;
    } catch (e) {
      final cached = await LocalStorageService.getCachedOrderDetails(orderId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    final res = await dispatch('create_order', payload);
    final map = Map<String, dynamic>.from(res ?? {});
    // Trigger background cache refresh
    getAllOrders().ignore();
    getDashboardStats().ignore();
    return map;
  }

  static Future<Map<String, dynamic>> getDeliveriesDashboard() async {
    try {
      final res = await dispatch('get_deliveries_dashboard');
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveDeliveries(map);
      return map;
    } catch (e) {
      final cached = await LocalStorageService.getCachedDeliveries();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  // Customer Details & Order History
  static Future<Map<String, dynamic>> getCustomerDetails(int customerId) async {
    try {
      final res = await dispatch('get_customer_details', {'id': customerId});
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveCustomerDetails(customerId, map);
      return map;
    } catch (e) {
      final cached = await LocalStorageService.getCachedCustomerDetails(customerId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  // Pending Payments / Orders
  static Future<List<dynamic>> getPendingOrders() async {
    try {
      final res = await dispatch('get_pending_orders');
      final list = List<dynamic>.from(res ?? []);
      await LocalStorageService.savePendingOrders(list);
      return list;
    } catch (e) {
      final cached = await LocalStorageService.getCachedPendingOrders();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  // Delete Order (Frees bill number for reuse)
  static Future<Map<String, dynamic>> deleteOrder(int orderId) async {
    final res = await dispatch('delete_order', {'id': orderId});
    getAllOrders().ignore();
    getDashboardStats().ignore();
    return Map<String, dynamic>.from(res ?? {});
  }

  // Create Payment
  static Future<Map<String, dynamic>> createPayment({
    required int orderId,
    required double amount,
    String paymentMethod = 'Cash',
    bool sendWhatsapp = true,
  }) async {
    final res = await dispatch('create_payment', {
      'order_id': orderId,
      'amount': amount,
      'payment_method': paymentMethod,
      'send_whatsapp': sendWhatsapp,
    });
    getAllOrders().ignore();
    getPendingOrders().ignore();
    getDashboardStats().ignore();
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> updateCustomer({
    required int id,
    required String name,
    required String mobile,
    String address = '',
    String notes = '',
  }) async {
    final res = await dispatch('update_customer', {
      'id': id,
      'name': name,
      'mobile': mobile,
      'address': address,
      'notes': notes,
    });
    getCustomers().ignore();
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> updateOrder({
    required int orderId,
    required List<Map<String, dynamic>> items,
    String? deliveryDate,
    String notes = '',
  }) async {
    final res = await dispatch('update_order', {
      'orderId': orderId,
      'deliveryDate': deliveryDate,
      'items': items,
      'notes': notes,
    });
    getAllOrders().ignore();
    getOrderDetails(orderId).ignore();
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> getShopSettings() async {
    try {
      final res = await dispatch('get_settings');
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveShopSettings(map);
      return map;
    } catch (_) {
      final cached = await LocalStorageService.getCachedShopSettings();
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      return {'shop_name': 'Haroon Tailor', 'currency_symbol': '₹'};
    }
  }

  static Future<Map<String, dynamic>> updateOrderStatus({
    required int orderId,
    required String status,
    bool sendWhatsapp = false,
    List<int>? deliveredItemIds,
    List<int>? readyItemIds,
  }) async {
    final payload = <String, dynamic>{
      'order_id': orderId,
      'status': status,
      'send_whatsapp': sendWhatsapp,
    };
    if (deliveredItemIds != null) payload['delivered_item_ids'] = deliveredItemIds;
    if (readyItemIds != null) payload['ready_item_ids'] = readyItemIds;
    final res = await dispatch('update_order_status', payload);
    getAllOrders().ignore();
    getOrderDetails(orderId).ignore();
    getDashboardStats().ignore();
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> updateShopSettings(Map<String, dynamic> settings) async {
    try {
      final res = await dispatch('update_settings', settings);
      final updated = await getShopSettings();
      await LocalStorageService.saveShopSettings(updated);
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      // Still persist locally
      await LocalStorageService.saveShopSettings(settings);
      return {'status': 'saved_locally', 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> createDatabaseBackup() async {
    try {
      final res = await dispatch('create_backup');
      return Map<String, dynamic>.from(res ?? {});
    } catch (e) {
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> exportFullMasterBackup() async {
    final res = await dispatch('export_full_master_backup');
    return Map<String, dynamic>.from(res ?? {});
  }
}

