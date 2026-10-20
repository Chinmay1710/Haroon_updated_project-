import 'dart:convert';
import 'package:http/http.dart' as http;

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
      );

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
    final res = await dispatch('get_dashboard_stats');
    return Map<String, dynamic>.from(res ?? {});
  }

  // Customers
  static Future<List<dynamic>> getCustomers() async {
    final res = await dispatch('get_customers');
    return List<dynamic>.from(res ?? []);
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
    return Map<String, dynamic>.from(res ?? {});
  }

  // Measurements
  static Future<List<dynamic>> getMeasurementsForCustomer(int customerId) async {
    final res = await dispatch('get_measurements_for_customer', {'customer_id': customerId});
    return List<dynamic>.from(res ?? []);
  }

  // Orders
  static Future<List<dynamic>> getAllOrders() async {
    final res = await dispatch('get_all_orders');
    return List<dynamic>.from(res ?? []);
  }

  static Future<Map<String, dynamic>> getOrderDetails(int orderId) async {
    final res = await dispatch('get_order_details', {'id': orderId});
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    final res = await dispatch('create_order', payload);
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<Map<String, dynamic>> getDeliveriesDashboard() async {
    final res = await dispatch('get_deliveries_dashboard');
    return Map<String, dynamic>.from(res ?? {});
  }

  static Future<void> updateOrderStatus({
    required int orderId,
    required String status,
    bool sendWhatsapp = false,
    List<int>? deliveredItemIds,
  }) async {
    await dispatch('update_order_status', {
      'order_id': orderId,
      'status': status,
      'send_whatsapp': sendWhatsapp,
      'delivered_item_ids': deliveredItemIds,
    });
  }
}
