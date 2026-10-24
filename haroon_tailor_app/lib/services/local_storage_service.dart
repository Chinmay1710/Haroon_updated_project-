import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/io_helper_stub.dart'
    if (dart.library.html) '../utils/io_helper_web.dart'
    if (dart.library.io) '../utils/io_helper_io.dart';

class LocalStorageService {
  static const String _keyOrders = 'ht_cache_orders';
  static const String _keyCustomers = 'ht_cache_customers';
  static const String _keyDashboard = 'ht_cache_dashboard';
  static const String _keyDeliveries = 'ht_cache_deliveries';
  static const String _keyPendingOrders = 'ht_cache_pending_orders';
  static const String _keySettings = 'ht_cache_settings';
  static const String _keyLastSync = 'ht_cache_last_sync';

  static bool _initialized = false;

  /// Initializes local storage, verifies disk files, and auto-seeds initial master data on first launch
  static Future<void> initStorage() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 1. Check if orders and customers exist on disk or in cache
      final existingCust = await getCachedCustomers();
      final existingOrders = await getCachedOrders();

      if ((existingCust == null || existingCust.isEmpty) &&
          (existingOrders == null || existingOrders.isEmpty)) {
        // First-time app open on client's phone: load bundled master data
        try {
          final seedRaw = await rootBundle.loadString('assets/data/initial_data.json');
          if (seedRaw.isNotEmpty) {
            final seed = jsonDecode(seedRaw);
            if (seed is Map<String, dynamic>) {
              await importMasterBackupMap(seed);
            }
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // ORDERS CACHE (Dual-Layer: Permanent Disk File + SharedPreferences)
  // -------------------------------------------------------------
  static Future<void> saveOrders(List<dynamic> orders) async {
    try {
      final jsonStr = jsonEncode(orders);
      // 1. Permanent file write directly to disk (never lost!)
      await saveJsonToFile('haroon_orders_data.json', jsonStr);
      // 2. Also keep SharedPreferences in sync
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyOrders, jsonStr);
      await _recordSyncTime();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedOrders() async {
    try {
      // 1. Try reading from permanent disk file
      final fromDisk = await readJsonFromFile('haroon_orders_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List && decoded.isNotEmpty) return decoded;
      }
      // 2. Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyOrders);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // Sync back to disk for durability
          await saveJsonToFile('haroon_orders_data.json', raw);
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // SINGLE ORDER DETAILS CACHE
  // -------------------------------------------------------------
  static Future<void> saveOrderDetails(int orderId, Map<String, dynamic> order) async {
    try {
      final cleanOrder = Map<String, dynamic>.from(order);
      if (cleanOrder['cloth_photos'] != null) {
        cleanOrder['cloth_photos'] = sanitizePhotoList(cleanOrder['cloth_photos']);
      }
      final jsonStr = jsonEncode(cleanOrder);
      await saveJsonToFile('haroon_order_$orderId.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_cache_order_$orderId', jsonStr);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedOrderDetails(int orderId) async {
    try {
      final fromDisk = await readJsonFromFile('haroon_order_$orderId.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is Map<String, dynamic>) {
          if (decoded['cloth_photos'] != null) {
            decoded['cloth_photos'] = sanitizePhotoList(decoded['cloth_photos']);
          }
          return decoded;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ht_cache_order_$orderId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          if (decoded['cloth_photos'] != null) {
            decoded['cloth_photos'] = sanitizePhotoList(decoded['cloth_photos']);
          }
          await saveJsonToFile('haroon_order_$orderId.json', raw);
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Safely extracts and sanitizes photo strings without breaking base64 data URLs.
  /// Discards broken fragments (like 'data:image/jpeg;base64' or raw comma-split base64 chunks)
  /// and ensures only intact, valid photo paths/URLs/data-URLs are returned without duplicates.
  static List<String> sanitizePhotoList(dynamic source) {
    final List<String> result = [];
    if (source == null) return result;

    void addCandidate(String? candidate) {
      if (candidate == null) return;
      final s = candidate.trim();
      if (s.isEmpty) return;
      if (s == 'null' || s == 'NULL' || s == 'undefined' || s == '[]' || s == '{}') return;

      // 1. Intact Data URL (e.g. data:image/jpeg;base64,xxxx)
      if (s.startsWith('data:image')) {
        final commaIdx = s.indexOf(',');
        // Must contain comma and at least 20 chars of payload
        if (commaIdx != -1 && s.length > commaIdx + 20) {
          if (!result.contains(s)) result.add(s);
        }
        return;
      }

      // 2. Broken header fragment (e.g. 'data:image/jpeg;base64' without payload)
      if (s.startsWith('data:') || s == 'base64') {
        return;
      }

      // 3. Broken payload fragment (e.g. comma-split tail starting with /9j/ or iVBORw0KGgo)
      if ((s.startsWith('/9j/') || s.startsWith('iVBORw0KGgo')) && !s.contains('.') && !s.contains('http')) {
        final alreadyPresent = result.any((existing) => existing.contains(s.substring(0, s.length > 30 ? 30 : s.length)));
        if (!alreadyPresent && s.length > 50) {
          final restored = 'data:image/jpeg;base64,$s';
          if (!result.contains(restored)) {
            result.add(restored);
          }
        }
        return;
      }

      // 4. Remote HTTP/HTTPS URLs, IndexedDB/local paths (photos/..., assets/...), or valid file extensions
      if (s.startsWith('http://') ||
          s.startsWith('https://') ||
          s.startsWith('photos/') ||
          s.startsWith('/photos/') ||
          s.startsWith('assets/') ||
          s.startsWith('blob:') ||
          s.toLowerCase().endsWith('.jpg') ||
          s.toLowerCase().endsWith('.jpeg') ||
          s.toLowerCase().endsWith('.png') ||
          s.toLowerCase().endsWith('.webp') ||
          s.toLowerCase().endsWith('.gif') ||
          (!s.contains('/') && s.length > 50)) {
        if (!result.contains(s)) result.add(s);
      }
    }

    void processString(String str) {
      final trimmed = str.trim();
      if (trimmed.isEmpty) return;

      if (trimmed.startsWith('data:image')) {
        // If multiple data URLs were joined together with comma
        if (trimmed.contains(',data:image')) {
          final parts = trimmed.split(',data:image');
          for (int i = 0; i < parts.length; i++) {
            final p = i == 0 ? parts[i] : 'data:image${parts[i]}';
            addCandidate(p);
          }
        } else {
          addCandidate(trimmed);
        }
      } else if (trimmed.contains(',')) {
        for (final part in trimmed.split(',')) {
          addCandidate(part);
        }
      } else {
        addCandidate(trimmed);
      }
    }

    if (source is List) {
      for (final item in source) {
        if (item is String) {
          processString(item);
        } else if (item != null) {
          processString(item.toString());
        }
      }
    } else if (source is String) {
      processString(source);
    }

    return result;
  }

  // -------------------------------------------------------------
  // CUSTOMERS CACHE
  // -------------------------------------------------------------
  static Future<void> saveCustomers(List<dynamic> customers) async {
    try {
      final jsonStr = jsonEncode(customers);
      await saveJsonToFile('haroon_customers_data.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonStr);
      await _recordSyncTime();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedCustomers() async {
    try {
      final fromDisk = await readJsonFromFile('haroon_customers_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List && decoded.isNotEmpty) return decoded;
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCustomers);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          await saveJsonToFile('haroon_customers_data.json', raw);
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------
  // OFFLINE-FIRST CRUD HELPERS (Ensures zero errors in Offline Mode)
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> saveCustomerOffline({
    int? id,
    required String name,
    required String mobile,
    String address = '',
    String notes = '',
  }) async {
    final cached = (await getCachedCustomers()) ?? [];
    final List<dynamic> customers = List<dynamic>.from(cached);

    int finalId = id ?? 0;
    if (finalId <= 0) {
      int maxId = 0;
      for (var c in customers) {
        if (c is Map && c['id'] is num) {
          final cid = (c['id'] as num).toInt();
          if (cid > maxId) maxId = cid;
        }
      }
      finalId = maxId > 0 ? maxId + 1 : (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    }

    final newCust = {
      'id': finalId,
      'name': name,
      'mobile': mobile,
      'address': address,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    };

    final index = customers.indexWhere((c) => c is Map && c['id'] == finalId);
    if (index >= 0) {
      customers[index] = newCust;
    } else {
      customers.insert(0, newCust);
    }

    await saveCustomers(customers);
    return newCust;
  }

  static Future<String> getNextBillNumber() async {
    final cached = (await getCachedOrders()) ?? [];
    int maxBill = 0;
    for (var o in cached) {
      if (o is Map) {
        final onumStr = (o['order_number'] ?? '').toString();
        final match = RegExp(r'\d+').allMatches(onumStr);
        if (match.isNotEmpty) {
          final lastDigits = match.last.group(0);
          final bNum = int.tryParse(lastDigits ?? '');
          if (bNum != null && bNum > maxBill) {
            maxBill = bNum;
          }
        }
      }
    }
    final nextBill = maxBill + 1;
    return 'Bill-${nextBill.toString().padLeft(6, '0')}';
  }

  static Future<Map<String, dynamic>> saveOrderOffline(Map<String, dynamic> payload) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);

    int finalId = (payload['id'] as num?)?.toInt() ?? 0;
    String billNo = (payload['order_number'] ?? '').toString();

    int maxId = 0;
    int maxBill = 0;
    for (var o in orders) {
      if (o is Map) {
        final idVal = o['id'];
        int idNum = 0;
        if (idVal is int) {
          idNum = idVal;
        } else if (idVal is num) {
          idNum = idVal.toInt();
        } else if (idVal != null) {
          idNum = int.tryParse(idVal.toString()) ?? 0;
        }
        if (idNum > maxId) maxId = idNum;

        final onumStr = (o['order_number'] ?? '').toString();
        final match = RegExp(r'\d+').allMatches(onumStr);
        if (match.isNotEmpty) {
          final lastDigits = match.last.group(0);
          final bNum = int.tryParse(lastDigits ?? '');
          if (bNum != null && bNum > maxBill) {
            maxBill = bNum;
          }
        }
      }
    }

    if (billNo.isEmpty || !billNo.startsWith('Bill-')) {
      final nextBill = maxBill + 1;
      billNo = 'Bill-${nextBill.toString().padLeft(6, '0')}';
    }
    if (finalId <= 0) {
      finalId = maxId > 0 ? maxId + 1 : 1;
    }

    final totalAmount = (payload['total_amount'] as num?)?.toDouble() ??
        (payload['subtotal'] as num?)?.toDouble() ??
        0.0;
    final advanceAmount = (payload['advance_amount'] as num?)?.toDouble() ??
        (payload['advance'] as num?)?.toDouble() ??
        0.0;
    final discount = (payload['discount'] as num?)?.toDouble() ?? 0.0;
    final remainingAmount = totalAmount - advanceAmount - discount;

    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final orderDate = (payload['order_date'] ?? todayStr).toString().split('T').first;
    final deliveryDate = (payload['delivery_date'] ?? payload['deliveryDate'] ?? '').toString().split('T').first;

    final rawItems = payload['items'];
    final List<dynamic> formattedItems = [];
    final List<String> gatheredPhotos = [];

    // Safely add cloth_photos from payload
    gatheredPhotos.addAll(sanitizePhotoList(payload['cloth_photos']));

    if (rawItems is List) {
      for (int i = 0; i < rawItems.length; i++) {
        if (rawItems[i] is Map) {
          final itemMap = Map<String, dynamic>.from(rawItems[i] as Map);
          if (itemMap['id'] == null || itemMap['id'] == 0) {
            itemMap['id'] = i + 1;
          }

          // Safely extract item photos without comma-splitting base64 data URLs
          final itemPhotos = <String>[];
          if (itemMap['image_base64'] != null) {
            itemPhotos.addAll(sanitizePhotoList(itemMap['image_base64']));
          }
          if (itemMap['image_path'] != null) {
            itemPhotos.addAll(sanitizePhotoList(itemMap['image_path']));
          }

          final cleanItemPhotos = sanitizePhotoList(itemPhotos);
          itemMap['image_base64'] = cleanItemPhotos.where((p) => p.startsWith('data:')).toList();
          itemMap['image_path'] = cleanItemPhotos.isNotEmpty ? cleanItemPhotos.first : '';

          for (final p in cleanItemPhotos) {
            if (!gatheredPhotos.contains(p)) {
              gatheredPhotos.add(p);
            }
          }

          formattedItems.add(itemMap);

          // Automatically save/update customer measurement profile for this clothing type
          final measMap = itemMap['measurements'];
          final cId = (payload['customer_id'] as num?)?.toInt() ?? (payload['customerId'] as num?)?.toInt() ?? 0;
          if (cId > 0 && measMap is Map && measMap.isNotEmpty) {
            saveCustomerMeasurementOffline(
              customerId: cId,
              clothingType: (itemMap['clothing_type'] ?? 'Garment').toString(),
              measurements: Map<String, dynamic>.from(measMap),
              sourceOrderNumber: billNo,
            ).ignore();
          }
        }
      }
    }

    final List<Map<String, dynamic>> rawItemsList = [];
    final List<String> itemSummaryParts = [];
    for (int i = 0; i < formattedItems.length; i++) {
      final it = formattedItems[i];
      final qty = it['quantity'] ?? 1;
      final type = it['clothing_type'] ?? 'Kapda';
      final nameStr = '$qty $type';
      itemSummaryParts.add(nameStr);
      rawItemsList.add({
        'id': it['id'] ?? (i + 1),
        'name': nameStr,
        'is_ready': it['is_ready'] == true,
      });
    }
    final summaryStr = itemSummaryParts.isNotEmpty
        ? itemSummaryParts.join(', ')
        : (payload['items_summary'] ?? 'Kapde').toString();

    final orderMap = {
      'id': finalId,
      'order_number': billNo,
      'customer_id': (payload['customer_id'] as num?)?.toInt() ?? (payload['customerId'] as num?)?.toInt() ?? 0,
      'customer_name': (payload['customer_name'] ?? 'Customer').toString(),
      'customer_mobile': (payload['customer_mobile'] ?? '').toString(),
      'customer_address': (payload['customer_address'] ?? '').toString(),
      'status': (payload['status'] ?? 'NEW').toString(),
      'order_date': orderDate,
      'delivery_date': deliveryDate,
      'total_amount': totalAmount,
      'advance_amount': advanceAmount,
      'discount': discount,
      'remaining_amount': remainingAmount < 0 ? 0.0 : remainingAmount,
      'notes': payload['notes'] ?? '',
      'special_instructions': payload['special_instructions'] ?? payload['notes'] ?? '',
      'items': summaryStr,
      'items_summary': summaryStr,
      'raw_items': rawItemsList,
      'items_detail': formattedItems,
      'payments': payload['payments'] is List
          ? payload['payments']
          : (orders.indexWhere((o) => o is Map && o['id']?.toString() == finalId.toString()) >= 0 &&
                  orders.firstWhere((o) => o is Map && o['id']?.toString() == finalId.toString())['payments'] is List
              ? orders.firstWhere((o) => o is Map && o['id']?.toString() == finalId.toString())['payments']
              : []),
      'cloth_photos': gatheredPhotos,
      'image_path': gatheredPhotos.where((p) => !p.startsWith('data:')).isNotEmpty
          ? gatheredPhotos.where((p) => !p.startsWith('data:')).join(',')
          : (gatheredPhotos.isNotEmpty ? gatheredPhotos.first : ''),
      'updated_at': DateTime.now().toIso8601String(),
    };

    final index = orders.indexWhere((o) => o is Map && o['id']?.toString() == finalId.toString());
    if (index >= 0) {
      orders[index] = orderMap;
    } else {
      orders.insert(0, orderMap); // Insert at 0 so it immediately appears at the top!
    }

    await saveOrders(orders);
    await saveOrderDetails(finalId, orderMap);
    await computeDashboardStatsFromOrders();
    await computePendingOrdersFromOrders();

    return {
      'status': 'success',
      'id': finalId,
      'order_number': billNo,
      'order': orderMap,
    };
  }

  static Future<Map<String, dynamic>> updateOrderStatusOffline({
    required int orderId,
    required String status,
    List<int>? readyItemIds,
    List<int>? deliveredItemIds,
  }) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);
    final index = orders.indexWhere((o) {
      if (o is! Map) return false;
      final idNum = int.tryParse((o['id'] ?? '').toString()) ?? 0;
      return idNum == orderId;
    });

    Map<String, dynamic>? targetOrder;
    if (index >= 0 && orders[index] is Map) {
      targetOrder = Map<String, dynamic>.from(orders[index] as Map);
      targetOrder['status'] = status;
      if (readyItemIds != null) {
        targetOrder['ready_item_ids'] = readyItemIds;
      }
      targetOrder['updated_at'] = DateTime.now().toIso8601String();

      // If raw_items exist, update is_ready for checkboxes
      if (targetOrder['raw_items'] is List) {
        final rawList = List<dynamic>.from(targetOrder['raw_items'] as List);
        for (int i = 0; i < rawList.length; i++) {
          if (rawList[i] is Map) {
            final itemMap = Map<String, dynamic>.from(rawList[i] as Map);
            final itemId = int.tryParse((itemMap['id'] ?? (i + 1)).toString()) ?? (i + 1);
            if (status == 'STITCHING_COMPLETE' || status == 'DELIVERED') {
              itemMap['is_ready'] = true;
            } else if (readyItemIds != null) {
              itemMap['is_ready'] = readyItemIds.contains(itemId);
            }
            rawList[i] = itemMap;
          }
        }
        targetOrder['raw_items'] = rawList;
      }

      // If items_detail exists, update it too
      if (targetOrder['items_detail'] is List) {
        final itemsList = List<dynamic>.from(targetOrder['items_detail'] as List);
        for (int i = 0; i < itemsList.length; i++) {
          if (itemsList[i] is Map) {
            final itemMap = Map<String, dynamic>.from(itemsList[i] as Map);
            final itemId = int.tryParse((itemMap['id'] ?? (i + 1)).toString()) ?? (i + 1);
            if (status == 'STITCHING_COMPLETE') {
              itemMap['is_ready'] = true;
              itemMap['status'] = 'READY';
            } else if (status == 'DELIVERED') {
              itemMap['is_ready'] = true;
              itemMap['status'] = 'DELIVERED';
            } else if (readyItemIds != null) {
              final isReady = readyItemIds.contains(itemId);
              itemMap['is_ready'] = isReady;
              itemMap['status'] = isReady ? 'READY' : 'IN_PROGRESS';
            }
            itemsList[i] = itemMap;
          }
        }
        targetOrder['items_detail'] = itemsList;
      }

      orders[index] = targetOrder;
      await saveOrders(orders);
    }

    // Also update order details cache
    final details = await getCachedOrderDetails(orderId);
    if (details != null && details.isNotEmpty) {
      final updatedDetails = Map<String, dynamic>.from(details);
      updatedDetails['status'] = status;
      updatedDetails['updated_at'] = DateTime.now().toIso8601String();

      if (updatedDetails['items'] is List) {
        final itemsList = List<dynamic>.from(updatedDetails['items'] as List);
        for (int i = 0; i < itemsList.length; i++) {
          if (itemsList[i] is Map) {
            final itemMap = Map<String, dynamic>.from(itemsList[i] as Map);
            final itemId = int.tryParse((itemMap['id'] ?? (i + 1)).toString()) ?? (i + 1);
            if (status == 'STITCHING_COMPLETE') {
              itemMap['is_ready'] = true;
              itemMap['status'] = 'READY';
            } else if (status == 'DELIVERED') {
              itemMap['is_ready'] = true;
              itemMap['status'] = 'DELIVERED';
            } else if (readyItemIds != null) {
              final isReady = readyItemIds.contains(itemId);
              itemMap['is_ready'] = isReady;
              itemMap['status'] = isReady ? 'READY' : 'IN_PROGRESS';
            } else if (deliveredItemIds != null) {
              final isDelivered = deliveredItemIds.contains(itemId);
              if (isDelivered) {
                itemMap['status'] = 'DELIVERED';
                itemMap['is_ready'] = true;
              }
            }
            itemsList[i] = itemMap;
          }
        }
        updatedDetails['items'] = itemsList;
      }
      await saveOrderDetails(orderId, updatedDetails);
    } else if (targetOrder != null) {
      await saveOrderDetails(orderId, targetOrder);
    }

    // Recompute dashboard stats and refresh deliveries and pending orders cache
    await computeDashboardStatsFromOrders();
    await computePendingOrdersFromOrders();

    return {
      'status': 'success',
      'order_id': orderId,
      'new_status': status,
    };
  }

  static Future<void> deleteOrderOffline(int orderId) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);
    final targetIdStr = orderId.toString();
    orders.removeWhere((o) => o is Map && o['id']?.toString() == targetIdStr);
    await saveOrders(orders);
    await computeDashboardStatsFromOrders();
    await computePendingOrdersFromOrders();
  }

  static Future<Map<String, dynamic>> createPaymentOffline({
    required int orderId,
    required double amount,
    String paymentMethod = 'Cash',
  }) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);
    final targetIdStr = orderId.toString();
    final index = orders.indexWhere((o) => o is Map && o['id']?.toString() == targetIdStr);

    if (index >= 0 && orders[index] is Map) {
      final order = Map<String, dynamic>.from(orders[index] as Map);
      final currentAdvance = (order['advance_amount'] as num?)?.toDouble() ?? double.tryParse((order['advance_amount'] ?? 0).toString()) ?? 0.0;
      final currentRemaining = (order['remaining_amount'] as num?)?.toDouble() ?? double.tryParse((order['remaining_amount'] ?? 0).toString()) ?? 0.0;

      final newAdvance = currentAdvance + amount;
      final newRemaining = (currentRemaining - amount) < 0 ? 0.0 : (currentRemaining - amount);

      order['advance_amount'] = newAdvance;
      order['remaining_amount'] = newRemaining;
      orders[index] = order;

      await saveOrders(orders);
      await saveOrderDetails(orderId, order);
      await computeDashboardStatsFromOrders();
      await computePendingOrdersFromOrders();
    }

    return {'status': 'success', 'order_id': orderId, 'amount': amount};
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
      final jsonStr = jsonEncode(measurements);
      await saveJsonToFile('haroon_measurements_$customerId.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ht_cache_measurements_$customerId', jsonStr);
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedMeasurements(int customerId) async {
    try {
      final fromDisk = await readJsonFromFile('haroon_measurements_$customerId.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List) return decoded;
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('ht_cache_measurements_$customerId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          await saveJsonToFile('haroon_measurements_$customerId.json', raw);
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveCustomerMeasurementOffline({
    required int customerId,
    required String clothingType,
    required Map<String, dynamic> measurements,
    String? sourceOrderNumber,
  }) async {
    if (customerId <= 0 || measurements.isEmpty) return;
    try {
      final existing = (await getCachedMeasurements(customerId)) ?? [];
      final List<dynamic> list = List<dynamic>.from(existing);

      final cleanType = clothingType.trim();
      final newProfile = {
        'id': list.length + 1,
        'customer_id': customerId,
        'name': cleanType + (sourceOrderNumber != null ? ' ($sourceOrderNumber)' : ''),
        'template_type': cleanType,
        'values': measurements,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final idx = list.indexWhere((p) =>
          p is Map &&
          (p['template_type'] ?? p['name'])?.toString().toLowerCase() == cleanType.toLowerCase());
      if (idx >= 0) {
        list[idx] = newProfile;
      } else {
        list.insert(0, newProfile);
      }

      await saveMeasurements(customerId, list);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getCustomerMeasurementsOffline(int customerId) async {
    final List<Map<String, dynamic>> results = [];
    final seenKeys = <String>{};

    // 1. Check explicitly saved customer profiles
    final cachedProfiles = await getCachedMeasurements(customerId);
    if (cachedProfiles != null && cachedProfiles.isNotEmpty) {
      for (var p in cachedProfiles) {
        if (p is Map) {
          final map = Map<String, dynamic>.from(p);
          final vals = (map['values'] as Map?) ?? {};
          if (vals.isNotEmpty) {
            final key = '${map['template_type'] ?? ''}_${vals.toString()}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              results.add(map);
            }
          }
        }
      }
    }

    // 2. Scan all previous orders of this customer for past garment measurements
    final orders = (await getCachedOrders()) ?? [];
    for (var o in orders) {
      if (o is! Map) continue;
      final cid = (o['customer_id'] as num?)?.toInt() ??
          (o['customerId'] as num?)?.toInt() ??
          int.tryParse(o['customer_id']?.toString() ?? '') ??
          int.tryParse(o['customerId']?.toString() ?? '');
      if (cid != customerId) continue;

      final billNo = o['order_number'] ?? '#${o['id']}';
      final orderDate = (o['order_date'] ?? '').toString();

      List<dynamic> items = [];
      if (o['items_detail'] is List && (o['items_detail'] as List).isNotEmpty) {
        items = o['items_detail'] as List;
      } else if (o['raw_items'] is List && (o['raw_items'] as List).isNotEmpty) {
        items = o['raw_items'] as List;
      } else if (o['items'] is List) {
        items = o['items'] as List;
      }

      for (var it in items) {
        if (it is! Map) continue;
        final cType = (it['clothing_type'] ?? it['type'] ?? 'Garment').toString();
        final rawMeas = it['measurements'];
        if (rawMeas is Map && rawMeas.isNotEmpty) {
          final Map<String, dynamic> cleanMeas = {};
          rawMeas.forEach((k, v) {
            if (v != null && v.toString().trim().isNotEmpty) {
              cleanMeas[k.toString().trim()] = v.toString().trim();
            }
          });

          if (cleanMeas.isNotEmpty) {
            final key = '${cType}_${cleanMeas.toString()}';
            if (!seenKeys.contains(key)) {
              seenKeys.add(key);
              results.add({
                'id': it['id'] ?? results.length + 1,
                'name': '$cType ($billNo)',
                'template_type': cType,
                'created_at': orderDate,
                'values': cleanMeas,
              });
            }
          }
        }
      }
    }

    return results;
  }

  static Future<Map<String, dynamic>> computeCustomerDetailsOffline(int customerId) async {
    final customers = (await getCachedCustomers()) ?? [];
    Map<String, dynamic>? customer;
    for (var c in customers) {
      if (c is Map) {
        final id = (c['id'] as num?)?.toInt() ?? int.tryParse(c['id']?.toString() ?? '');
        if (id == customerId) {
          customer = Map<String, dynamic>.from(c);
          break;
        }
      }
    }

    final orders = (await getCachedOrders()) ?? [];
    final customerOrders = orders.where((o) {
      if (o is! Map) return false;
      final cid = (o['customer_id'] as num?)?.toInt() ??
          (o['customerId'] as num?)?.toInt() ??
          int.tryParse(o['customer_id']?.toString() ?? '') ??
          int.tryParse(o['customerId']?.toString() ?? '');
      return cid == customerId;
    }).toList();

    if (customer == null) {
      String name = 'Customer';
      String phone = '';
      String address = '';
      String notes = '';
      if (customerOrders.isNotEmpty) {
        final first = customerOrders.first as Map;
        name = (first['customer_name'] ?? 'Customer').toString();
        phone = (first['customer_mobile'] ?? '').toString();
        address = (first['customer_address'] ?? '').toString();
      }
      customer = {
        'id': customerId,
        'name': name,
        'mobile': phone,
        'address': address,
        'notes': notes,
      };
    }

    final profiles = await getCustomerMeasurementsOffline(customerId);

    final result = {
      'customer': customer,
      'orders': customerOrders,
      'profiles': profiles,
    };

    await saveCustomerDetails(customerId, result);
    return result;
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
        if (decoded is Map<String, dynamic>) {
          if (decoded['recent_orders'] != null &&
              (decoded['recent_orders'] as List).isNotEmpty &&
              decoded['pending_payments'] != null) {
            return decoded;
          }
        }
      }
    } catch (_) {}

    // Auto-heal from cached orders if stats was empty or missing keys
    return await computeDashboardStatsFromOrders();
  }

  static Future<Map<String, dynamic>> computeDashboardStatsFromOrders() async {
    final orders = await getCachedOrders();
    if (orders == null || orders.isEmpty) {
      return {
        'total_orders': 0,
        'active_orders': 0,
        'delivered_orders': 0,
        'total_revenue': 0,
        'pending_balance': 0,
        'pending_payments': 0,
        'orders_today': 0,
        'deliveries_today': 0,
        'completed_today': 0,
        'recent_orders': [],
      };
    }

    final todayStr = DateTime.now().toIso8601String().split('T').first;
    double totalRevenue = 0.0;
    double pendingBalance = 0.0;
    int activeOrders = 0;
    int deliveredOrders = 0;
    int ordersToday = 0;
    int deliveriesToday = 0;
    final List<dynamic> deliveriesList = [];

    for (var o in orders) {
      if (o is Map) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final remaining = (o['remaining_amount'] as num?)?.toDouble() ?? 0.0;
        final status = o['status']?.toString().toUpperCase() ?? 'NEW';
        final oDate = (o['order_date'] ?? '').toString();
        final dDate = (o['delivery_date'] ?? '').toString();

        if (status == 'DELIVERED') {
          deliveredOrders++;
        } else if (status != 'CANCELLED') {
          activeOrders++;
        }

        totalRevenue += (total - remaining);
        if (remaining > 0) {
          pendingBalance += remaining;
        }

        if (oDate.startsWith(todayStr)) {
          ordersToday++;
        }

        // Only add to deliveries if stitching is complete (user clicked Complete button)
        // This matches the website workflow: orders appear in deliveries only after Complete
        final isReadyForDelivery = status == 'STITCHING_COMPLETE' || status == 'PARTIALLY_COMPLETE';
        if (isReadyForDelivery) {
          deliveriesList.add(o);
          if (dDate.startsWith(todayStr) || (dDate.isNotEmpty && dDate.compareTo(todayStr) <= 0)) {
            deliveriesToday++;
          }
        }
      }
    }

    final recentOrders = orders.take(15).map((o) {
      if (o is Map) {
        return {
          'id': o['id'],
          'order_number': o['order_number'] ?? '#${o['id']}',
          'customer_name': o['customer_name'] ?? 'Customer',
          'status': o['status'] ?? 'NEW',
          'total_amount': o['total_amount'] ?? 0,
          'remaining_amount': o['remaining_amount'] ?? 0,
          'order_date': o['order_date'] ?? '',
          'delivery_date': o['delivery_date'] ?? '',
          'image_path': o['image_path'] ?? '',
        };
      }
      return o;
    }).toList();

    final stats = {
      'total_orders': orders.length,
      'active_orders': activeOrders,
      'delivered_orders': deliveredOrders,
      'total_revenue': totalRevenue,
      'pending_balance': pendingBalance,
      'pending_payments': pendingBalance,
      'orders_today': ordersToday,
      'deliveries_today': deliveriesToday,
      'completed_today': 0,
      'recent_orders': recentOrders,
    };

    await saveDashboardStats(stats);
    await saveDeliveries({'deliveries': deliveriesList});

    return stats;
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
        if (decoded is List && decoded.isNotEmpty) return decoded;
      }
    } catch (_) {}
    return await computePendingOrdersFromOrders();
  }

  static Future<List<dynamic>> computePendingOrdersFromOrders() async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> pending = [];
    for (var o in cached) {
      if (o is Map) {
        double remaining = (o['remaining_amount'] as num?)?.toDouble() ??
            double.tryParse((o['remaining_amount'] ?? 0).toString()) ??
            0.0;
        final status = (o['status'] ?? '').toString().toUpperCase();

        // If remaining is not recorded or 0, check total - (advance + discount)
        if (remaining <= 0.01 && status != 'CANCELLED') {
          final total = (o['total_amount'] as num?)?.toDouble() ??
              double.tryParse((o['total_amount'] ?? 0).toString()) ??
              0.0;
          final adv = (o['advance_amount'] as num?)?.toDouble() ??
              double.tryParse((o['advance_amount'] ?? 0).toString()) ??
              0.0;
          final disc = (o['discount'] as num?)?.toDouble() ??
              double.tryParse((o['discount'] ?? 0).toString()) ??
              0.0;
          if (total > (adv + disc)) {
            remaining = total - (adv + disc);
            o['remaining_amount'] = remaining;
          }
        }

        if (remaining > 0.01 && status != 'CANCELLED') {
          final item = Map<String, dynamic>.from(o);
          item['remaining_amount'] = remaining;
          pending.add(item);
        }
      }
    }
    await savePendingOrders(pending);
    return pending;
  }

  // -------------------------------------------------------------
  // SHOP SETTINGS CACHE
  // -------------------------------------------------------------
  static Future<void> saveShopSettings(Map<String, dynamic> settings) async {
    try {
      final jsonStr = jsonEncode(settings);
      await saveJsonToFile('haroon_settings_data.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySettings, jsonStr);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedShopSettings() async {
    try {
      final fromDisk = await readJsonFromFile('haroon_settings_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is Map<String, dynamic>) return decoded;
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keySettings);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          await saveJsonToFile('haroon_settings_data.json', raw);
          return decoded;
        }
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
      final fromDisk = await readJsonFromFile('haroon_templates_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is Map) {
          final res = Map<String, String>.from(defaultMessageTemplates);
          decoded.forEach((k, v) {
            if (v != null) res[k.toString()] = v.toString();
          });
          return res;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyMsgTemplates);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final res = Map<String, String>.from(defaultMessageTemplates);
          decoded.forEach((k, v) {
            if (v != null) res[k.toString()] = v.toString();
          });
          await saveJsonToFile('haroon_templates_data.json', raw);
          return res;
        }
      }
    } catch (_) {}
    return Map<String, String>.from(defaultMessageTemplates);
  }

  static Future<void> saveMessageTemplates(Map<String, String> templates) async {
    try {
      final jsonStr = jsonEncode(templates);
      await saveJsonToFile('haroon_templates_data.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMsgTemplates, jsonStr);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // NOTES SUGGESTIONS
  // -------------------------------------------------------------
  static const String _keyNotesSuggestions = 'ht_notes_suggestions';

  static List<String> get defaultNotesSuggestions => [
    'Collar Chinese',
    'Collar Regular',
    'Collar Button Down',
    'Single Pocket',
    'Double Pocket',
    'Without Pocket',
    'Cuff Square',
    'Cuff Cut',
    'Fitting Loose',
    'Fitting Normal',
    'Fitting Slim',
    'Side Slit',
    'Belt Loop Extra',
    'Back Pocket Single',
    'Back Pocket Double',
    'Watch Pocket',
    'Plate Single',
    'Plate Double',
    'Cross Pocket',
    'Straight Pocket',
  ];

  static Future<List<String>> getNotesSuggestions() async {
    try {
      final fromDisk = await readJsonFromFile('haroon_notes_suggestions.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List) {
          final list = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          if (list.isNotEmpty) return list;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyNotesSuggestions);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
          if (list.isNotEmpty) {
            await saveJsonToFile('haroon_notes_suggestions.json', raw);
            return list;
          }
        }
      }
    } catch (_) {}
    return List<String>.from(defaultNotesSuggestions);
  }

  static Future<void> saveNotesSuggestions(List<String> list) async {
    try {
      final jsonStr = jsonEncode(list);
      await saveJsonToFile('haroon_notes_suggestions.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyNotesSuggestions, jsonStr);
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
      return prefs.getString(_keyAppTheme) ?? 'light';
    } catch (_) {
      return 'light';
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

  static Future<String> exportFullMasterBackupJson() async {
    final orders = await getCachedOrders();
    final customers = await getCachedCustomers();
    final settings = await getCachedShopSettings();

    final List<dynamic> detailedOrders = [];
    int totalPhotos = 0;
    int totalMeasurements = 0;

    if (orders != null) {
      for (var o in orders) {
        if (o is Map && o['id'] != null) {
          final det = await getCachedOrderDetails(o['id'] as int);
          final orderData = det ?? o;
          detailedOrders.add(orderData);

          List<dynamic> items = [];
          if (orderData['raw_items'] is List) {
            items = orderData['raw_items'] as List;
          } else if (orderData['items'] is List) {
            items = orderData['items'] as List;
          } else if (o['raw_items'] is List) {
            items = o['raw_items'] as List;
          }
          for (var it in items) {
            if (it is Map) {
              if ((it['image_path']?.toString() ?? '').isNotEmpty) {
                totalPhotos++;
              }
              final meas = it['measurements'] as Map<String, dynamic>? ?? {};
              totalMeasurements += meas.length;
            }
          }
        }
      }
    }

    final Map<String, dynamic> backupData = {
      'app': 'Haroon Tailor',
      'version': '1.0.0',
      'export_timestamp': DateTime.now().toIso8601String(),
      'total_customers': customers?.length ?? 0,
      'total_orders': detailedOrders.length,
      'total_photos': totalPhotos,
      'total_measurements': totalMeasurements,
      'settings': settings ?? {},
      'customers': customers ?? [],
      'orders': detailedOrders,
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
  // MASTER BACKUP RESTORE (Full 360 Orders, Photos, Measurements, Customers)
  // -------------------------------------------------------------
  static Future<Map<String, dynamic>> importMasterBackupMap(Map<String, dynamic> data) async {
    int importedCustomers = 0;
    int importedOrders = 0;
    int totalPhotos = 0;
    int totalMeasurements = 0;

    try {
      // 1. Settings
      if (data['settings'] is Map) {
        final settings = Map<String, dynamic>.from(data['settings']);
        await saveShopSettings(settings);
        if (settings['clothing_types'] != null) {
          final typesStr = settings['clothing_types'].toString();
          final typesList = typesStr
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (typesList.isNotEmpty) {
            await saveGarmentTypes(typesList);
          }
        }
      }

      // 2. Customers
      final customersRaw = data['customers'];
      if (customersRaw is List) {
        final List<dynamic> customersList = [];
        for (var c in customersRaw) {
          if (c is Map) {
            final custMap = Map<String, dynamic>.from(c);
            customersList.add(custMap);
            final custId = custMap['id'];
            if (custId is int) {
              await saveCustomerDetails(custId, {
                'customer': custMap,
                'profiles': custMap['profiles'] ?? [],
              });
            }
            importedCustomers++;
          }
        }
        await saveCustomers(customersList);
      }

      // 2.1 Customer Measurements
      if (data['customer_measurements'] is Map) {
        final measMap = data['customer_measurements'] as Map;
        for (var entry in measMap.entries) {
          final cid = int.tryParse(entry.key.toString());
          if (cid != null && entry.value is List) {
            await saveMeasurements(cid, entry.value as List);
          }
        }
      }

      // 3. Orders
      final ordersRaw = data['orders'];
      if (ordersRaw is List) {
        final List<dynamic> ordersSummaryList = [];
        final List<dynamic> pendingOrdersList = [];
        double totalRevenue = 0.0;
        double pendingBalance = 0.0;
        int activeOrders = 0;
        int deliveredOrders = 0;

        for (var o in ordersRaw) {
          if (o is Map) {
            final orderMap = Map<String, dynamic>.from(o);
            final orderId = orderMap['id'];
            final remaining = (orderMap['remaining_amount'] as num?)?.toDouble() ?? 0.0;
            final total = (orderMap['total_amount'] as num?)?.toDouble() ?? 0.0;
            final status = orderMap['status']?.toString().toUpperCase() ?? 'NEW';

            // Save deep order details (with items, 24 measurements, photos, payments)
            if (orderId is int) {
              await saveOrderDetails(orderId, orderMap);
            }

            // Summary format for list view
            String itemsSummary = orderMap['items_summary']?.toString() ?? '';
            if (itemsSummary.isEmpty && orderMap['items'] is String) {
              itemsSummary = orderMap['items'] as String;
            }
            String photoUrl = '';
            List<dynamic> items = [];
            if (orderMap['raw_items'] is List) {
              items = orderMap['raw_items'] as List;
            } else if (orderMap['items'] is List) {
              items = orderMap['items'] as List;
            }
            for (var it in items) {
              if (it is Map) {
                final p = it['image_path']?.toString() ?? '';
                if (p.isNotEmpty) {
                  photoUrl = p;
                  totalPhotos++;
                }
                final meas = it['measurements'] as Map<String, dynamic>? ?? {};
                totalMeasurements += meas.length;
              }
            }

            if (photoUrl.isEmpty) {
              final topImg = orderMap['image_path']?.toString() ?? '';
              if (topImg.isNotEmpty) {
                photoUrl = topImg.split(',').first.trim();
                totalPhotos++;
              }
            }

            final summaryItem = {
              'id': orderId,
              'order_number': orderMap['order_number'] ?? 'Bill-$orderId',
              'customer_name': orderMap['customer_name'] ?? 'Unknown',
              'customer_id': orderMap['customer_id'],
              'customer_mobile': orderMap['customer_mobile'] ?? '',
              'items': itemsSummary.isNotEmpty ? itemsSummary : 'Garments',
              'raw_items': items,
              'image_path': photoUrl,
              'order_date': orderMap['order_date'] ?? '',
              'delivery_date': orderMap['delivery_date'] ?? '',
              'status': status,
              'total_amount': total,
              'discount': (orderMap['discount'] as num?)?.toDouble() ?? 0.0,
              'remaining_amount': remaining,
              'updated_at': orderMap['updated_at'] ?? '',
            };

            ordersSummaryList.add(summaryItem);

            if (remaining > 0) {
              pendingOrdersList.add(summaryItem);
              pendingBalance += remaining;
            }

            if (status == 'DELIVERED') {
              deliveredOrders++;
            } else if (status != 'CANCELLED') {
              activeOrders++;
            }

            totalRevenue += (total - remaining);
            importedOrders++;
          }
        }

        await saveOrders(ordersSummaryList);
        await savePendingOrders(pendingOrdersList);

        // Compute full dashboard stats & deliveries
        final todayStr = DateTime.now().toIso8601String().split('T').first;
        int ordersToday = 0;
        int deliveriesToday = 0;
        final List<dynamic> deliveriesList = [];

        for (var o in ordersSummaryList) {
          final oDate = (o['order_date'] ?? '').toString();
          if (oDate.startsWith(todayStr)) {
            ordersToday++;
          }

          final dDate = (o['delivery_date'] ?? '').toString();
          final s = (o['status'] ?? '').toString();
          final isUndelivered = s != 'DELIVERED' && s != 'CANCELLED';

          if (isUndelivered) {
            deliveriesList.add(o);
            if (dDate.startsWith(todayStr) || (dDate.isNotEmpty && dDate.compareTo(todayStr) <= 0)) {
              deliveriesToday++;
            }
          }
        }

        final recentOrders = ordersSummaryList.take(15).map((o) => {
          'id': o['id'],
          'order_number': o['order_number'] ?? '#${o['id']}',
          'customer_name': o['customer_name'] ?? 'Customer',
          'status': o['status'] ?? 'NEW',
          'total_amount': o['total_amount'] ?? 0,
          'remaining_amount': o['remaining_amount'] ?? 0,
          'order_date': o['order_date'] ?? '',
          'delivery_date': o['delivery_date'] ?? '',
          'image_path': o['image_path'] ?? '',
        }).toList();

        final stats = {
          'total_orders': importedOrders,
          'active_orders': activeOrders,
          'delivered_orders': deliveredOrders,
          'total_revenue': totalRevenue,
          'pending_balance': pendingBalance,
          'pending_payments': pendingBalance,
          'orders_today': ordersToday,
          'deliveries_today': deliveriesToday,
          'completed_today': 0,
          'recent_orders': recentOrders,
        };
        await saveDashboardStats(stats);
        if (deliveriesList.isNotEmpty) {
          await saveDeliveries({'deliveries': deliveriesList});
        }
      }

      await _recordSyncTime();

      return {
        'success': true,
        'customers_count': importedCustomers,
        'orders_count': importedOrders,
        'photos_count': totalPhotos,
        'measurements_count': totalMeasurements,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> importMasterBackupJson(String rawJson) async {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return {'success': false, 'error': 'Invalid JSON format'};
      }
      return await importMasterBackupMap(decoded);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // -------------------------------------------------------------
  // OFFLINE MODE
  // -------------------------------------------------------------
  static const String _keyOfflineMode = 'ht_offline_mode_active';

  static Future<bool> isOfflineMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyOfflineMode) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setOfflineMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOfflineMode, enabled);
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // AUTO BACKUP SETTINGS
  // -------------------------------------------------------------
  static const String _keyAutoBackupEnabled = 'ht_auto_backup_enabled';
  static const String _keyAutoBackupFreq = 'ht_auto_backup_freq';
  static const String _keyLastAutoBackupTime = 'ht_last_auto_backup_time';

  static Future<bool> isAutoBackupEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyAutoBackupEnabled) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setAutoBackupEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoBackupEnabled, enabled);
    } catch (_) {}
  }

  static Future<String> getAutoBackupFrequency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyAutoBackupFreq) ?? 'daily';
    } catch (_) {
      return 'daily';
    }
  }

  static Future<void> setAutoBackupFrequency(String freq) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAutoBackupFreq, freq);
    } catch (_) {}
  }

  static Future<String?> getLastAutoBackupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyLastAutoBackupTime);
    } catch (_) {
      return null;
    }
  }

  static Future<void> recordAutoBackupTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastAutoBackupTime, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // CLEAR CACHE
  // -------------------------------------------------------------
  static Future<void> clearAll({bool enableOfflineMode = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (enableOfflineMode) {
        await prefs.setBool(_keyOfflineMode, true);
      }
    } catch (_) {}
  }
}


