import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_storage_service.dart';

class ApiService {
  static const String baseUrl = 'https://haroon-tailor.onrender.com';
  static const String dispatchEndpoint = '$baseUrl/admin-api/dispatch';

  static Future<dynamic> dispatch(String action, [Map<String, dynamic>? payload]) async {
    if (await LocalStorageService.isOfflineMode()) {
      throw Exception('Offline mode active (cloud sync paused)');
    }
    try {
      final response = await http.post(
        Uri.parse(dispatchEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': action,
          'payload': payload ?? {},
        }),
      ).timeout(const Duration(seconds: 6));

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
      return {
        'total_orders': 0,
        'active_orders': 0,
        'delivered_orders': 0,
        'total_revenue': 0,
        'pending_balance': 0,
        'completed_today': 0,
        'recent_orders': [],
      };
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
      if (cached != null) {
        return cached;
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> createCustomer({
    required String name,
    required String mobile,
    String address = '',
    String notes = '',
  }) async {
    // 1. Instantly save offline locally first (zero waiting, 100% reliable)
    final localSaved = await LocalStorageService.saveCustomerOffline(
      name: name,
      mobile: mobile,
      address: address,
      notes: notes,
    );

    // 2. Sync to cloud backend in background if online
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('create_customer', {
          'name': name,
          'mobile': mobile,
          'address': address,
          'notes': notes,
        });
        final map = Map<String, dynamic>.from(res ?? {});
        if (map['id'] != null) {
          await LocalStorageService.saveCustomerOffline(
            id: (map['id'] as num?)?.toInt(),
            name: name,
            mobile: mobile,
            address: address,
            notes: notes,
          );
        }
        getCustomers().ignore();
        return {
          ...map,
          'id': map['id'] ?? localSaved['id'],
        };
      } catch (_) {}
    }
    return localSaved;
  }

  // Measurements
  static Future<List<dynamic>> getMeasurementsForCustomer(int customerId) async {
    final offlineMeasurements = await LocalStorageService.getCustomerMeasurementsOffline(customerId);
    if (offlineMeasurements.isNotEmpty) {
      return offlineMeasurements;
    }
    if (await LocalStorageService.isOfflineMode()) {
      return offlineMeasurements;
    }
    try {
      final res = await dispatch('get_measurements_for_customer', {'customer_id': customerId});
      final list = List<dynamic>.from(res ?? []);
      await LocalStorageService.saveMeasurements(customerId, list);
      return list.isNotEmpty ? list : offlineMeasurements;
    } catch (_) {
      return offlineMeasurements;
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
      if (cached != null) {
        return cached;
      }
      return [];
    }
  }

  static Future<Map<String, dynamic>> getOrderDetails(int orderId) async {
    if (await LocalStorageService.isOfflineMode()) {
      final cached = await LocalStorageService.getCachedOrderDetails(orderId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      final orders = (await LocalStorageService.getCachedOrders()) ?? [];
      for (var o in orders) {
        if (o is Map && (o['id']?.toString() == orderId.toString())) {
          return Map<String, dynamic>.from(o);
        }
      }
      return {};
    }
    try {
      final res = await dispatch('get_order_details', {'id': orderId});
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveOrderDetails(orderId, map);
      return map;
    } catch (_) {
      final cached = await LocalStorageService.getCachedOrderDetails(orderId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      final orders = (await LocalStorageService.getCachedOrders()) ?? [];
      for (var o in orders) {
        if (o is Map && (o['id']?.toString() == orderId.toString())) {
          return Map<String, dynamic>.from(o);
        }
      }
      return {};
    }
  }

  static Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    final savedLocal = await LocalStorageService.saveOrderOffline(payload);

    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('create_order', payload);
        final map = Map<String, dynamic>.from(res ?? {});
        if (map['id'] != null || map['order_number'] != null) {
          await LocalStorageService.saveOrderOffline({
            ...payload,
            if (map['id'] != null) 'id': map['id'],
            if (map['order_number'] != null && map['order_number'].toString().startsWith('Bill-'))
              'order_number': map['order_number'],
          });
        }
        getAllOrders().ignore();
        getDashboardStats().ignore();
        return {
          ...map,
          'order_number': savedLocal['order_number'] ?? map['order_number'],
          'id': savedLocal['id'] ?? map['id'],
        };
      } catch (_) {}
    }
    return savedLocal;
  }

  static Future<Map<String, dynamic>> getDeliveriesDashboard() async {
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('get_deliveries_dashboard');
        final map = Map<String, dynamic>.from(res ?? {});
        await LocalStorageService.saveDeliveries(map);
        return map;
      } catch (_) {}
    }
    // Offline mode: compute dynamically from local orders
    final orders = (await LocalStorageService.getCachedOrders()) ?? [];
    final readyList = orders.where((o) {
      if (o is! Map) return false;
      final s = (o['status'] ?? '').toString();
      return s == 'STITCHING_COMPLETE' || s == 'PARTIALLY_COMPLETE';
    }).toList();

    final map = {
      'deliveries': readyList,
      'today': [],
      'upcoming': [],
      'overdue': [],
    };
    await LocalStorageService.saveDeliveries(map);
    return map;
  }

  // Customer Details & Order History
  static Future<Map<String, dynamic>> getCustomerDetails(int customerId) async {
    if (await LocalStorageService.isOfflineMode()) {
      final cached = await LocalStorageService.getCachedCustomerDetails(customerId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      return await LocalStorageService.computeCustomerDetailsOffline(customerId);
    }
    try {
      final res = await dispatch('get_customer_details', {'id': customerId});
      final map = Map<String, dynamic>.from(res ?? {});
      await LocalStorageService.saveCustomerDetails(customerId, map);
      return map;
    } catch (_) {
      final cached = await LocalStorageService.getCachedCustomerDetails(customerId);
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      return await LocalStorageService.computeCustomerDetailsOffline(customerId);
    }
  }

  // Pending Payments / Orders
  static Future<List<dynamic>> getPendingOrders() async {
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('get_pending_orders');
        final list = List<dynamic>.from(res ?? []);
        if (list.isNotEmpty) {
          await LocalStorageService.savePendingOrders(list);
          return list;
        }
      } catch (_) {}
    }
    // Offline mode or cloud returned empty: dynamically compute from local orders
    return await LocalStorageService.computePendingOrdersFromOrders();
  }

  // Delete Order (Frees bill number for reuse)
  static Future<Map<String, dynamic>> deleteOrder(int orderId) async {
    await LocalStorageService.deleteOrderOffline(orderId);
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('delete_order', {'id': orderId});
        return Map<String, dynamic>.from(res ?? {});
      } catch (_) {}
    }
    return {'status': 'success', 'id': orderId};
  }

  // Create Payment
  static Future<Map<String, dynamic>> createPayment({
    required int orderId,
    required double amount,
    String paymentMethod = 'Cash',
    bool sendWhatsapp = true,
  }) async {
    await LocalStorageService.createPaymentOffline(
      orderId: orderId,
      amount: amount,
      paymentMethod: paymentMethod,
    );
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('create_payment', {
          'order_id': orderId,
          'amount': amount,
          'payment_method': paymentMethod,
          'send_whatsapp': sendWhatsapp,
        });
        return Map<String, dynamic>.from(res ?? {});
      } catch (_) {}
    }
    return {'status': 'success', 'order_id': orderId, 'amount': amount};
  }

  static Future<Map<String, dynamic>> updateCustomer({
    required int id,
    required String name,
    required String mobile,
    String address = '',
    String notes = '',
  }) async {
    if (await LocalStorageService.isOfflineMode()) {
      return await LocalStorageService.saveCustomerOffline(
        id: id,
        name: name,
        mobile: mobile,
        address: address,
        notes: notes,
      );
    }
    try {
      final res = await dispatch('update_customer', {
        'id': id,
        'name': name,
        'mobile': mobile,
        'address': address,
        'notes': notes,
      });
      await LocalStorageService.saveCustomerOffline(
        id: id,
        name: name,
        mobile: mobile,
        address: address,
        notes: notes,
      );
      getCustomers().ignore();
      return Map<String, dynamic>.from(res ?? {});
    } catch (_) {
      return await LocalStorageService.saveCustomerOffline(
        id: id,
        name: name,
        mobile: mobile,
        address: address,
        notes: notes,
      );
    }
  }

  static Future<Map<String, dynamic>> updateOrder({
    required int orderId,
    Map<String, dynamic>? orderPayload,
    List<Map<String, dynamic>>? items,
    String? deliveryDate,
    String notes = '',
  }) async {
    Map<String, dynamic> fullData;
    if (orderPayload != null) {
      fullData = Map<String, dynamic>.from(orderPayload);
      fullData['id'] = orderId;
    } else {
      final cached = await LocalStorageService.getCachedOrderDetails(orderId) ?? {};
      fullData = Map<String, dynamic>.from(cached);
      fullData['id'] = orderId;
      if (items != null) fullData['items'] = items;
      if (deliveryDate != null) fullData['delivery_date'] = deliveryDate;
      if (notes.isNotEmpty) fullData['notes'] = notes;
    }

    final localSaved = await LocalStorageService.saveOrderOffline(fullData);
    await LocalStorageService.saveOrderDetails(orderId, localSaved['order'] ?? fullData);

    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final res = await dispatch('update_order', {
          'orderId': orderId,
          'id': orderId,
          'deliveryDate': fullData['delivery_date'] ?? deliveryDate,
          'items': fullData['items'] ?? items,
          'notes': fullData['notes'] ?? notes,
          'total_amount': fullData['total_amount'],
          'advance_amount': fullData['advance_amount'],
          'discount': fullData['discount'],
          'cloth_photos': fullData['cloth_photos'],
        });
        return Map<String, dynamic>.from(res ?? {});
      } catch (_) {}
    }
    return localSaved;
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
    // 1. Update local offline storage first (instant zero-latency UI update)
    final localResult = await LocalStorageService.updateOrderStatusOffline(
      orderId: orderId,
      status: status,
      readyItemIds: readyItemIds,
      deliveredItemIds: deliveredItemIds,
    );

    // 2. If online mode is active, attempt to dispatch to backend server
    if (!await LocalStorageService.isOfflineMode()) {
      try {
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
      } catch (_) {
        // Cloud sync paused or failed, local update succeeded
      }
    }

    return localResult;
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

