import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  // In-memory performance cache layer (eliminates redundant disk reads & JSON decodes)
  static List<dynamic>? _memoryOrdersCache;
  static List<dynamic>? _memoryCustomersCache;
  static final Map<int, Map<String, dynamic>> _memoryOrderDetailsCache = {};
  static final Map<int, List<Map<String, dynamic>>> _memoryMeasurementsCache = {};

  // Safety snapshot for rollback on restore failures
  static Map<String, dynamic>? _safetySnapshot;

  // Data change notification hook for Google Drive auto-sync
  static void Function()? onDataChanged;
  static void notifyDataChanged() {
    onDataChanged?.call();
  }

  /// Initializes local storage, verifies disk files, and auto-seeds initial master data on first launch
  static const String _keyCleanFreshState = 'ht_is_clean_fresh_state';

  static Future<void> initStorage() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final isCleanFresh = prefs.getBool(_keyCleanFreshState) ?? false;
      if (isCleanFresh) {
        // User explicitly started a fresh offline app; do not auto-seed
        return;
      }

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
      _memoryOrdersCache = List<dynamic>.from(orders);
      final jsonStr = jsonEncode(orders);
      // 1. Permanent file write directly to disk (never lost!)
      await saveJsonToFile('haroon_orders_data.json', jsonStr);
      // 2. Also keep SharedPreferences in sync
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyOrders, jsonStr);
      await _recordSyncTime();
      notifyDataChanged();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedOrders() async {
    if (_memoryOrdersCache != null) return _memoryOrdersCache;
    try {
      // 1. Try reading from permanent disk file
      final fromDisk = await readJsonFromFile('haroon_orders_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List) {
          _memoryOrdersCache = decoded;
          return decoded;
        }
      }
      // 2. Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyOrders);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // Sync back to disk for durability
          _memoryOrdersCache = decoded;
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
      _memoryOrderDetailsCache[orderId] = cleanOrder;
      final jsonStr = jsonEncode(cleanOrder);
      await saveJsonToFile('haroon_order_$orderId.json', jsonStr);
      notifyDataChanged();
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getCachedOrderDetails(int orderId) async {
    if (_memoryOrderDetailsCache.containsKey(orderId)) {
      return _memoryOrderDetailsCache[orderId];
    }
    try {
      final fromDisk = await readJsonFromFile('haroon_order_$orderId.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is Map<String, dynamic>) {
          if (decoded['cloth_photos'] != null) {
            decoded['cloth_photos'] = sanitizePhotoList(decoded['cloth_photos']);
          }
          _memoryOrderDetailsCache[orderId] = decoded;
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
          _memoryOrderDetailsCache[orderId] = decoded;
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
      _memoryCustomersCache = List<dynamic>.from(customers);
      final jsonStr = jsonEncode(customers);
      await saveJsonToFile('haroon_customers_data.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomers, jsonStr);
      await _recordSyncTime();
      notifyDataChanged();
    } catch (_) {}
  }

  static Future<List<dynamic>?> getCachedCustomers() async {
    if (_memoryCustomersCache != null) return _memoryCustomersCache;
    try {
      final fromDisk = await readJsonFromFile('haroon_customers_data.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is List) {
          _memoryCustomersCache = decoded;
          return decoded;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyCustomers);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _memoryCustomersCache = decoded;
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

    final index = orders.indexWhere((o) =>
        (finalId > 0 && orderMatchesId(o, finalId)) ||
        (billNo.isNotEmpty && o is Map && (o['order_number'] ?? '').toString() == billNo));
    if (index >= 0) {
      orders[index] = orderMap;
    } else {
      orders.insert(0, orderMap); // Insert at 0 so it immediately appears at the top!
    }

    await saveOrders(orders);
    await saveOrderDetails(finalId, orderMap);
    await computeDashboardStatsFromOrders();
    await computePendingOrdersFromOrders();

    int customerId = (orderMap['customer_id'] as num?)?.toInt() ??
        (orderMap['customerId'] as num?)?.toInt() ??
        int.tryParse(orderMap['customer_id']?.toString() ?? '') ??
        0;
    if (customerId <= 0) {
      final cMobile = (orderMap['customer_mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
      final allCusts = (await getCachedCustomers()) ?? [];
      for (var c in allCusts) {
        if (c is Map) {
          final m = (c['mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
          if (cMobile.isNotEmpty && m.isNotEmpty && (m == cMobile || m.endsWith(cMobile) || cMobile.endsWith(m))) {
            customerId = int.tryParse(c['id']?.toString() ?? '') ?? 0;
            break;
          }
        }
      }
    }
    if (customerId > 0) {
      await computeCustomerDetailsOffline(customerId);
    }

    return {
      'status': 'success',
      'id': finalId,
      'order_number': billNo,
      'order': orderMap,
    };
  }

  static bool orderMatchesId(dynamic o, int targetId) {
    if (o is! Map) return false;
    if (targetId <= 0) return false;
    final idVal = o['id'];
    if (idVal == targetId) return true;
    final idNum = int.tryParse(idVal?.toString() ?? '');
    if (idNum != null && idNum > 0 && idNum == targetId) return true;
    if (idVal?.toString() == targetId.toString()) return true;

    final onumStr = (o['order_number'] ?? '').toString();
    if (onumStr == targetId.toString()) return true;
    final match = RegExp(r'\d+').allMatches(onumStr);
    if (match.isNotEmpty) {
      final billDigits = int.tryParse(match.last.group(0) ?? '');
      if (billDigits != null && billDigits == targetId) return true;
    }
    return false;
  }

  static Future<Map<String, dynamic>> updateOrderStatusOffline({
    required int orderId,
    required String status,
    List<int>? readyItemIds,
    List<int>? deliveredItemIds,
  }) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);
    int index = orders.indexWhere((o) => orderMatchesId(o, orderId));

    Map<String, dynamic>? targetOrder;
    if (index >= 0 && orders[index] is Map) {
      targetOrder = Map<String, dynamic>.from(orders[index] as Map);
    } else {
      // Fallback: Check cached individual order details
      final details = await getCachedOrderDetails(orderId);
      if (details != null && details.isNotEmpty) {
        targetOrder = Map<String, dynamic>.from(details);
        final bNo = (targetOrder['order_number'] ?? '').toString();
        if (bNo.isNotEmpty) {
          index = orders.indexWhere((o) => o is Map && (o['order_number'] ?? '').toString() == bNo);
        }
      }
    }

    if (targetOrder != null) {
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

      // If items exist, update it too
      if (targetOrder['items'] is List) {
        final itemsList = List<dynamic>.from(targetOrder['items'] as List);
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
        targetOrder['items'] = itemsList;
      }

      bool updatedAny = false;
      final billNumStr = (targetOrder['order_number'] ?? '').toString().trim();
      for (int i = 0; i < orders.length; i++) {
        if (orders[i] is Map) {
          final oMap = orders[i] as Map;
          final oBNo = (oMap['order_number'] ?? '').toString().trim();
          if (orderMatchesId(oMap, orderId) || (billNumStr.isNotEmpty && oBNo.isNotEmpty && oBNo == billNumStr)) {
            orders[i] = targetOrder;
            updatedAny = true;
          }
        }
      }
      if (!updatedAny) {
        orders.insert(0, targetOrder);
      }
      await saveOrders(orders);

      // Save order details cache under orderId, altId, and bill number digits
      await saveOrderDetails(orderId, targetOrder);
      final altId = int.tryParse((targetOrder['id'] ?? '').toString());
      if (altId != null && altId > 0 && altId != orderId) {
        await saveOrderDetails(altId, targetOrder);
      }
      final bNoDigits = int.tryParse(RegExp(r'\d+').allMatches(billNumStr).lastOrNull?.group(0) ?? '');
      if (bNoDigits != null && bNoDigits > 0 && bNoDigits != orderId && bNoDigits != altId) {
        await saveOrderDetails(bNoDigits, targetOrder);
      }

      // Recompute dashboard stats and refresh deliveries and pending orders cache
      await computeDashboardStatsFromOrders();
      await computePendingOrdersFromOrders();

      // Synchronize customer profile so updated status immediately reflects there
      int? matchedCustomerId = int.tryParse((targetOrder['customer_id'] ?? targetOrder['customerId'] ?? '').toString());
      if (matchedCustomerId == null || matchedCustomerId <= 0) {
        final cMobile = (targetOrder['customer_mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
        final allCusts = (await getCachedCustomers()) ?? [];
        for (var c in allCusts) {
          if (c is Map) {
            final m = (c['mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
            if (cMobile.isNotEmpty && m.isNotEmpty && (m == cMobile || m.endsWith(cMobile) || cMobile.endsWith(m))) {
              matchedCustomerId = int.tryParse(c['id']?.toString() ?? '');
              break;
            }
          }
        }
      }
      if (matchedCustomerId != null && matchedCustomerId > 0) {
        await computeCustomerDetailsOffline(matchedCustomerId);
      }
    }

    return {
      'status': 'success',
      'order_id': orderId,
      'new_status': status,
    };
  }

  static Future<void> deleteOrderOffline(int orderId) async {
    final cached = (await getCachedOrders()) ?? [];
    final List<dynamic> orders = List<dynamic>.from(cached);
    orders.removeWhere((o) => orderMatchesId(o, orderId));
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
    int index = orders.indexWhere((o) => orderMatchesId(o, orderId));

    Map<String, dynamic>? targetOrder;
    if (index >= 0 && orders[index] is Map) {
      targetOrder = Map<String, dynamic>.from(orders[index] as Map);
    } else {
      // Fallback: check order details cache
      final details = await getCachedOrderDetails(orderId);
      if (details != null && details.isNotEmpty) {
        targetOrder = Map<String, dynamic>.from(details);
        final bNo = (targetOrder['order_number'] ?? '').toString();
        if (bNo.isNotEmpty) {
          index = orders.indexWhere((o) => o is Map && (o['order_number'] ?? '').toString() == bNo);
        }
      }
    }

    if (targetOrder != null) {
      final currentAdvance = (targetOrder['advance_amount'] as num?)?.toDouble() ??
          double.tryParse((targetOrder['advance_amount'] ?? 0).toString()) ??
          0.0;
      final currentRemaining = (targetOrder['remaining_amount'] as num?)?.toDouble() ??
          double.tryParse((targetOrder['remaining_amount'] ?? 0).toString()) ??
          0.0;

      final newAdvance = currentAdvance + amount;
      final newRemaining = (currentRemaining - amount) < 0 ? 0.0 : (currentRemaining - amount);

      targetOrder['advance_amount'] = newAdvance;
      targetOrder['remaining_amount'] = newRemaining;

      // Add payment entry to payments list
      final List<dynamic> paymentsList = targetOrder['payments'] is List
          ? List<dynamic>.from(targetOrder['payments'] as List)
          : [];
      paymentsList.add({
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_date': DateTime.now().toIso8601String(),
      });
      targetOrder['payments'] = paymentsList;

      bool updatedAny = false;
      final billNumStr = (targetOrder['order_number'] ?? '').toString().trim();
      for (int i = 0; i < orders.length; i++) {
        if (orders[i] is Map) {
          final oMap = orders[i] as Map;
          final oBNo = (oMap['order_number'] ?? '').toString().trim();
          if (orderMatchesId(oMap, orderId) || (billNumStr.isNotEmpty && oBNo.isNotEmpty && oBNo == billNumStr)) {
            orders[i] = targetOrder;
            updatedAny = true;
          }
        }
      }
      if (!updatedAny) {
        orders.insert(0, targetOrder);
      }
      await saveOrders(orders);

      // Save order details cache under orderId, altId, and bill number digits
      await saveOrderDetails(orderId, targetOrder);
      final altId = int.tryParse((targetOrder['id'] ?? '').toString());
      if (altId != null && altId > 0 && altId != orderId) {
        await saveOrderDetails(altId, targetOrder);
      }
      final bNoDigits = int.tryParse(RegExp(r'\d+').allMatches(billNumStr).lastOrNull?.group(0) ?? '');
      if (bNoDigits != null && bNoDigits > 0 && bNoDigits != orderId && bNoDigits != altId) {
        await saveOrderDetails(bNoDigits, targetOrder);
      }

      await computeDashboardStatsFromOrders();
      await computePendingOrdersFromOrders();

      // Synchronize customer profile so updated payment and balance immediately reflect
      int? matchedCustomerId = int.tryParse((targetOrder['customer_id'] ?? targetOrder['customerId'] ?? '').toString());
      if (matchedCustomerId == null || matchedCustomerId <= 0) {
        final cMobile = (targetOrder['customer_mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
        final allCusts = (await getCachedCustomers()) ?? [];
        for (var c in allCusts) {
          if (c is Map) {
            final m = (c['mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
            if (cMobile.isNotEmpty && m.isNotEmpty && (m == cMobile || m.endsWith(cMobile) || cMobile.endsWith(m))) {
              matchedCustomerId = int.tryParse(c['id']?.toString() ?? '');
              break;
            }
          }
        }
      }
      if (matchedCustomerId != null && matchedCustomerId > 0) {
        await computeCustomerDetailsOffline(matchedCustomerId);
      }
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

  static Future<List<Map<String, dynamic>>> getCustomerMeasurementsOffline(
    int customerId, [
    List<dynamic>? preloadedOrders,
  ]) async {
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
    final orders = preloadedOrders ?? (await getCachedOrders()) ?? [];
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

    if (customer == null) {
      final existingCache = await getCachedCustomerDetails(customerId);
      if (existingCache != null && existingCache['customer'] is Map) {
        customer = Map<String, dynamic>.from(existingCache['customer']);
      }
    }

    final String custMobile = (customer?['mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();

    final orders = (await getCachedOrders()) ?? [];
    final customerOrders = orders.where((o) {
      if (o is! Map) return false;
      final cid = (o['customer_id'] as num?)?.toInt() ??
          (o['customerId'] as num?)?.toInt() ??
          int.tryParse(o['customer_id']?.toString() ?? '') ??
          int.tryParse(o['customerId']?.toString() ?? '');
      if (cid != null && cid > 0 && cid == customerId) return true;

      if (custMobile.isNotEmpty) {
        final oMobile = (o['customer_mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
        if (oMobile.isNotEmpty && (oMobile == custMobile || oMobile.endsWith(custMobile) || custMobile.endsWith(oMobile))) {
          return true;
        }
      }
      return false;
    }).toList();

    // Deduplicate customer orders and enrich from single order details cache
    final seenKeys = <String>{};
    final uniqueCustomerOrders = <Map<String, dynamic>>[];
    for (var o in customerOrders) {
      if (o is! Map) continue;
      final oMap = Map<String, dynamic>.from(o);
      final bNo = (oMap['order_number'] ?? '').toString().trim();
      final oId = (oMap['id'] ?? '').toString().trim();
      final key = bNo.isNotEmpty ? bNo : (oId.isNotEmpty ? 'id_$oId' : '');
      if (key.isNotEmpty && seenKeys.contains(key)) {
        continue;
      }
      if (key.isNotEmpty) seenKeys.add(key);

      // Check if there is a more up-to-date single order cache for this order
      final oIdNum = int.tryParse(oId) ?? 0;
      if (oIdNum > 0) {
        final cachedDetail = await getCachedOrderDetails(oIdNum);
        if (cachedDetail != null && cachedDetail.isNotEmpty) {
          if (cachedDetail['status'] != null) oMap['status'] = cachedDetail['status'];
          if (cachedDetail['remaining_amount'] != null) oMap['remaining_amount'] = cachedDetail['remaining_amount'];
          if (cachedDetail['advance_amount'] != null) oMap['advance_amount'] = cachedDetail['advance_amount'];
          if (cachedDetail['total_amount'] != null) oMap['total_amount'] = cachedDetail['total_amount'];
          if (cachedDetail['payments'] != null) oMap['payments'] = cachedDetail['payments'];
        }
      }
      uniqueCustomerOrders.add(oMap);
    }

    // Calculate customer total pending amount from the latest orders
    double calculatedPending = 0.0;
    for (var o in uniqueCustomerOrders) {
      final rem = (o['remaining_amount'] as num?)?.toDouble() ??
          double.tryParse((o['remaining_amount'] ?? 0).toString()) ??
          0.0;
      calculatedPending += rem;
    }

    if (customer == null) {
      String name = 'Customer';
      String phone = '';
      String address = '';
      String notes = '';
      if (uniqueCustomerOrders.isNotEmpty) {
        final first = uniqueCustomerOrders.first;
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
        'pending_amount': calculatedPending,
        'orders_count': uniqueCustomerOrders.length,
      };
    } else {
      customer['pending_amount'] = calculatedPending;
      customer['orders_count'] = uniqueCustomerOrders.length;

      // Also update customer in the cached customers list so customers_screen has the updated due
      try {
        final allCusts = (await getCachedCustomers()) ?? [];
        final List<dynamic> updatedCusts = List<dynamic>.from(allCusts);
        final cIdx = updatedCusts.indexWhere((c) {
          if (c is! Map) return false;
          final cid = (c['id'] as num?)?.toInt() ?? int.tryParse(c['id']?.toString() ?? '');
          return cid == customerId;
        });
        if (cIdx >= 0 && updatedCusts[cIdx] is Map) {
          final cMap = Map<String, dynamic>.from(updatedCusts[cIdx] as Map);
          cMap['pending_amount'] = calculatedPending;
          cMap['orders_count'] = uniqueCustomerOrders.length;
          updatedCusts[cIdx] = cMap;
          await saveCustomers(updatedCusts);
        }
      } catch (_) {}
    }

    List<dynamic> profiles = await getCustomerMeasurementsOffline(customerId);
    if (profiles.isEmpty) {
      final existingCache = await getCachedCustomerDetails(customerId);
      if (existingCache != null && existingCache['profiles'] is List && (existingCache['profiles'] as List).isNotEmpty) {
        profiles = List<dynamic>.from(existingCache['profiles']);
      }
    }

    final result = {
      'customer': customer,
      'orders': uniqueCustomerOrders,
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
          if (decoded['recent_orders'] is List &&
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
        'urgent_orders': 0,
        'total_revenue': 0,
        'pending_balance': 0,
        'pending_payments': 0,
        'orders_today': 0,
        'deliveries_today': 0,
        'completed_today': 0,
        'recent_orders': <dynamic>[],
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

  static Future<bool> editGarmentType({
    required String oldName,
    required String newName,
  }) async {
    final cleanOld = oldName.trim();
    final cleanNew = newName.trim();
    if (cleanOld.isEmpty || cleanNew.isEmpty) return false;
    if (cleanOld.toLowerCase() == cleanNew.toLowerCase()) return true;

    final current = await getGarmentTypes();
    final index = current.indexWhere((t) => t.toLowerCase() == cleanOld.toLowerCase());
    if (index == -1) return false;

    // 1. Rename in list
    current[index] = cleanNew;
    await saveGarmentTypes(current);

    // 2. Transfer default rate
    try {
      final rates = await getDefaultRates();
      if (rates.containsKey(cleanOld)) {
        final rate = rates.remove(cleanOld)!;
        rates[cleanNew] = rate;
        await saveDefaultRates(rates);
      }
    } catch (_) {}

    // 3. Transfer clothing notes suggestions
    try {
      final notesMap = await getClothingNotesMap();
      if (notesMap.containsKey(cleanOld)) {
        final notes = notesMap.remove(cleanOld)!;
        notesMap[cleanNew] = notes;
        await saveClothingNotesSuggestions(notesMap);
      }
    } catch (_) {}

    return true;
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
  // CLOTHING-TYPE SPECIFIC NOTES SUGGESTIONS
  // -------------------------------------------------------------
  static const String _keyNotesSuggestions = 'ht_notes_suggestions';
  static const String _keyClothingNotes = 'ht_clothing_notes_suggestions';

  static Map<String, List<String>> get defaultClothingNotesMap => {
    'Shirt': [
      'Collar Normal',
      'Collar Chinese',
      'Collar Mandar',
      'Collar Button Down',
      'Cuff Single Button',
      'Cuff Double Button',
      'Pocket Single Left',
      'Pocket Double',
      'Without Pocket',
      'Fitting Slim',
      'Fitting Regular',
      'Fitting Loose',
      'Bottom Round (Apple Cut)',
      'Bottom Flat',
      'Front Patti Concealed',
      'Front Patti Normal',
    ],
    'Pant': [
      'Cross Pocket',
      'Straight Pocket',
      'Back Pocket Single',
      'Back Pocket Double',
      'Watch Pocket',
      'Plate Single',
      'Plate Double',
      'Without Plate (Flat Front)',
      'Belt Loop Extra',
      'Belt Loop Normal',
      'Grip Belt',
      'Fitting Slim',
      'Fitting Regular',
      'Narrow Bottom',
      'Straight Bottom',
    ],
    'Kurta': [
      'Collar Chinese',
      'Collar Normal',
      'Kurta Patti Designer',
      'Side Pocket Left',
      'Side Pocket Right',
      'Both Side Pockets',
      'Side Slit High',
      'Fitting Regular',
      'Sleeve Fold Open',
      'Cuff Sleeve',
    ],
    'Pajama': [
      'Churidar',
      'Straight Cut',
      'Elastic Waist',
      'Nada Waist',
      'Side Pocket Single',
      'Side Pocket Double',
      'Fitting Loose',
    ],
    'Safari Suit': [
      'Safari Collar',
      'Four Pockets Front',
      'Shoulder Flap (Epaulet)',
      'Belt Back',
      'Safari Half Sleeve',
      'Safari Full Sleeve',
      'Side Vent Single',
    ],
    'Blazer / Coat': [
      'Single Breasted',
      'Double Breasted',
      'Two Buttons',
      'One Button',
      'Peak Lapel',
      'Notch Lapel',
      'Double Vent (Cut)',
      'Single Vent (Cut)',
      'Inside Pocket Both Sides',
    ],
    'Sadri / Waistcoat': [
      'Mandarin Collar',
      'V-Neck',
      '5 Buttons',
      '6 Buttons',
      'Two Pockets Front',
      'Chest Pocket',
      'Fitting Slim',
    ],
  };

  static List<String> get defaultNotesSuggestions {
    final Set<String> all = {};
    for (var list in defaultClothingNotesMap.values) {
      all.addAll(list);
    }
    return all.toList();
  }

  static Future<Map<String, List<String>>> getClothingNotesMap() async {
    try {
      final fromDisk = await readJsonFromFile('haroon_clothing_notes.json');
      if (fromDisk != null && fromDisk.isNotEmpty) {
        final decoded = jsonDecode(fromDisk);
        if (decoded is Map) {
          final res = <String, List<String>>{};
          decoded.forEach((k, v) {
            if (v is List) {
              res[k.toString()] = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
            }
          });
          if (res.isNotEmpty) return res;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyClothingNotes);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final res = <String, List<String>>{};
          decoded.forEach((k, v) {
            if (v is List) {
              res[k.toString()] = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
            }
          });
          if (res.isNotEmpty) {
            await saveJsonToFile('haroon_clothing_notes.json', raw);
            return res;
          }
        }
      }
    } catch (_) {}

    return Map<String, List<String>>.from(
      defaultClothingNotesMap.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
  }

  static Future<void> saveClothingNotesSuggestions(Map<String, List<String>> map) async {
    try {
      final jsonStr = jsonEncode(map);
      await saveJsonToFile('haroon_clothing_notes.json', jsonStr);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyClothingNotes, jsonStr);
    } catch (_) {}
  }

  static Future<List<String>> getNotesSuggestionsForType(String clothingType) async {
    final cleanType = clothingType.trim();
    final map = await getClothingNotesMap();

    // 1. Direct match
    if (map.containsKey(cleanType) && map[cleanType]!.isNotEmpty) {
      return List<String>.from(map[cleanType]!);
    }

    // 2. Case-insensitive match
    for (var entry in map.entries) {
      if (entry.key.toLowerCase() == cleanType.toLowerCase() && entry.value.isNotEmpty) {
        return List<String>.from(entry.value);
      }
    }

    // 3. Partial match (e.g. "Full Shirt" -> "Shirt")
    for (var entry in map.entries) {
      if ((cleanType.toLowerCase().contains(entry.key.toLowerCase()) ||
              entry.key.toLowerCase().contains(cleanType.toLowerCase())) &&
          entry.value.isNotEmpty) {
        return List<String>.from(entry.value);
      }
    }

    return defaultNotesSuggestions;
  }

  static Future<void> addClothingNoteSuggestion({
    required String clothingType,
    required String note,
  }) async {
    final cleanType = clothingType.trim();
    final cleanNote = note.trim();
    if (cleanType.isEmpty || cleanNote.isEmpty) return;

    final map = await getClothingNotesMap();
    final list = map.putIfAbsent(cleanType, () => []);
    if (!list.any((s) => s.toLowerCase() == cleanNote.toLowerCase())) {
      list.add(cleanNote);
      await saveClothingNotesSuggestions(map);
    }
  }

  static Future<void> removeClothingNoteSuggestion({
    required String clothingType,
    required String note,
  }) async {
    final cleanType = clothingType.trim();
    final cleanNote = note.trim();
    if (cleanType.isEmpty || cleanNote.isEmpty) return;

    final map = await getClothingNotesMap();
    if (map.containsKey(cleanType)) {
      map[cleanType]!.removeWhere((s) => s.toLowerCase() == cleanNote.toLowerCase());
      await saveClothingNotesSuggestions(map);
    }
  }

  static Future<void> resetClothingNotesSuggestions({String? clothingType}) async {
    final defaultMap = defaultClothingNotesMap;
    if (clothingType != null && clothingType.trim().isNotEmpty) {
      final clean = clothingType.trim();
      final currentMap = await getClothingNotesMap();
      currentMap[clean] = List<String>.from(defaultMap[clean] ?? defaultNotesSuggestions);
      await saveClothingNotesSuggestions(currentMap);
    } else {
      await saveClothingNotesSuggestions(Map<String, List<String>>.from(
        defaultMap.map((k, v) => MapEntry(k, List<String>.from(v))),
      ));
    }
  }

  static Future<List<String>> getNotesSuggestions() async {
    final map = await getClothingNotesMap();
    final Set<String> all = {};
    for (var l in map.values) {
      all.addAll(l);
    }
    if (all.isNotEmpty) return all.toList();
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
  // MASTER BACKUP RESTORE (Full Orders, Photos, Measurements, Customers)
  // -------------------------------------------------------------
  static Future<void> createSafetySnapshot() async {
    try {
      _safetySnapshot = {
        'orders': await getCachedOrders(),
        'customers': await getCachedCustomers(),
        'dashboard': await getCachedDashboardStats(),
        'settings': await getCachedShopSettings(),
        'pending_orders': await getCachedPendingOrders(),
        'deliveries': await getCachedDeliveries(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (_) {}
  }

  static Future<bool> restoreSafetySnapshot() async {
    if (_safetySnapshot == null) return false;
    try {
      if (_safetySnapshot!['orders'] != null) {
        await saveOrders(List<dynamic>.from(_safetySnapshot!['orders']));
      }
      if (_safetySnapshot!['customers'] != null) {
        await saveCustomers(List<dynamic>.from(_safetySnapshot!['customers']));
      }
      if (_safetySnapshot!['settings'] != null) {
        await saveShopSettings(Map<String, dynamic>.from(_safetySnapshot!['settings']));
      }
      if (_safetySnapshot!['dashboard'] != null) {
        await saveDashboardStats(Map<String, dynamic>.from(_safetySnapshot!['dashboard']));
      }
      if (_safetySnapshot!['pending_orders'] != null) {
        await savePendingOrders(List<dynamic>.from(_safetySnapshot!['pending_orders']));
      }
      if (_safetySnapshot!['deliveries'] != null) {
        await saveDeliveries(Map<String, dynamic>.from(_safetySnapshot!['deliveries']));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Conflict detection: Checks if current local data has records modified more recently than the backup's export timestamp
  static Future<bool> isLocalDataNewerThan(String? backupTimestamp) async {
    if (backupTimestamp == null || backupTimestamp.isEmpty) return false;
    try {
      final backupDt = DateTime.parse(backupTimestamp);
      final orders = await getCachedOrders();
      if (orders == null || orders.isEmpty) return false;
      for (var o in orders) {
        if (o is Map) {
          final updatedStr = (o['updated_at'] ?? o['order_date'] ?? '').toString();
          if (updatedStr.isNotEmpty) {
            final orderDt = DateTime.tryParse(updatedStr);
            if (orderDt != null && orderDt.isAfter(backupDt.add(const Duration(minutes: 5)))) {
              return true;
            }
          }
        }
      }
    } catch (_) {}
    return false;
  }

  static int _safeInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  static double _safeDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static Future<Map<String, dynamic>> importMasterBackupMap(Map<String, dynamic> data) async {
    // 0. Create safety snapshot of current data before modifying anything
    await createSafetySnapshot();

    int importedCustomers = 0;
    int importedOrders = 0;
    int totalPhotos = 0;
    int totalMeasurements = 0;

    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyCleanFreshState);
      } catch (e) {
        debugPrint('Prefs init warning: $e');
      }

      // 1. Settings (safely guarded so settings failure never halts order restore)
      try {
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

        if (data['clothing_types'] is List) {
          await saveGarmentTypes(List<String>.from(data['clothing_types']));
        }

        if (data['message_templates'] is Map) {
          await saveMessageTemplates(Map<String, String>.from(data['message_templates']));
        }

        if (data['default_rates'] is Map) {
          final rates = (data['default_rates'] as Map).map(
            (k, v) => MapEntry(k.toString(), _safeDouble(v)),
          );
          await saveDefaultRates(rates);
        }

        if (data['app_theme'] is String && (data['app_theme'] as String).isNotEmpty) {
          await saveAppTheme(data['app_theme'] as String);
        }

        if (data['app_language'] is String && (data['app_language'] as String).isNotEmpty) {
          await saveAppLanguage(data['app_language'] as String);
        }

        if (data['measurement_unit'] is String && (data['measurement_unit'] as String).isNotEmpty) {
          await saveMeasurementUnit(data['measurement_unit'] as String);
        }

        if (data['default_delivery_days'] != null) {
          await saveDefaultDeliveryDays(_safeInt(data['default_delivery_days'], 3));
        }

        if (data['notes_suggestions'] is List) {
          await saveNotesSuggestions(List<String>.from(data['notes_suggestions']));
        }

        if (data['clothing_notes_suggestions'] is Map) {
          final map = <String, List<String>>{};
          (data['clothing_notes_suggestions'] as Map).forEach((k, v) {
            if (v is List) {
              map[k.toString()] = v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
            }
          });
          if (map.isNotEmpty) {
            await saveClothingNotesSuggestions(map);
          }
        }

        if (data['auto_backup_enabled'] is bool) {
          await setAutoBackupEnabled(data['auto_backup_enabled'] as bool);
        }

        if (data['auto_backup_frequency'] is String && (data['auto_backup_frequency'] as String).isNotEmpty) {
          await setAutoBackupFrequency(data['auto_backup_frequency'] as String);
        }
      } catch (settingsErr) {
        debugPrint('Settings import non-fatal error: $settingsErr');
      }

      // 2. Customers
      final customersRaw = data['customers'];
      if (customersRaw is List) {
        final List<dynamic> customersList = [];
        for (var c in customersRaw) {
          if (c is Map) {
            final custMap = Map<String, dynamic>.from(c);
            final custId = _safeInt(custMap['id']);
            if (custId > 0) {
              custMap['id'] = custId;
              await saveCustomerDetails(custId, {
                'customer': custMap,
                'profiles': custMap['profiles'] ?? [],
              });
            }
            customersList.add(custMap);
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
            final int parsedOrderId = _safeInt(orderMap['id']);
            final remaining = _safeDouble(orderMap['remaining_amount']);
            final total = _safeDouble(orderMap['total_amount']);
            final advance = _safeDouble(orderMap['advance_amount']);
            final discount = _safeDouble(orderMap['discount']);
            
            // Preserve exact status verbatim without forced uppercase mutation
            final String rawStatus = (orderMap['status'] ?? orderMap['order_status'] ?? 'NEW').toString();
            final String status = rawStatus.isNotEmpty ? rawStatus : 'NEW';

            // Summary format for list view
            String itemsSummary = orderMap['items_summary']?.toString() ?? '';
            if (itemsSummary.isEmpty && orderMap['items'] is String) {
              itemsSummary = orderMap['items'] as String;
            }
            String photoUrl = '';
            List<dynamic> items = [];
            if (orderMap['raw_items'] is List) {
              items = List<dynamic>.from(orderMap['raw_items'] as List);
            } else if (orderMap['items'] is List) {
              items = List<dynamic>.from(orderMap['items'] as List);
            }

            final List<dynamic> readyItemIds = [];
            final List<dynamic> deliveredItemIds = [];
            if (orderMap['ready_item_ids'] is List) {
              readyItemIds.addAll(orderMap['ready_item_ids'] as List);
            }
            if (orderMap['delivered_item_ids'] is List) {
              deliveredItemIds.addAll(orderMap['delivered_item_ids'] as List);
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

                final itId = it['id'];
                if (itId != null) {
                  if (it['is_ready'] == true && !readyItemIds.contains(itId)) {
                    readyItemIds.add(itId);
                  }
                  if (it['is_delivered'] == true && !deliveredItemIds.contains(itId)) {
                    deliveredItemIds.add(itId);
                  }
                }
              }
            }

            if (photoUrl.isEmpty) {
              final topImg = orderMap['image_path']?.toString() ?? '';
              if (topImg.isNotEmpty) {
                photoUrl = topImg.split(',').first.trim();
                totalPhotos++;
              }
            }

            // Save deep order details (with items, measurements, photos, payments)
            if (parsedOrderId > 0) {
              orderMap['id'] = parsedOrderId;
              orderMap['total_amount'] = total;
              orderMap['advance_amount'] = advance;
              orderMap['remaining_amount'] = remaining;
              orderMap['discount'] = discount;
              orderMap['ready_item_ids'] = readyItemIds;
              orderMap['delivered_item_ids'] = deliveredItemIds;
              orderMap['status'] = status;
              await saveOrderDetails(parsedOrderId, orderMap);
            }

            final summaryItem = {
              'id': parsedOrderId,
              'order_number': orderMap['order_number'] ?? 'Bill-$parsedOrderId',
              'customer_name': orderMap['customer_name'] ?? 'Unknown',
              'customer_id': _safeInt(orderMap['customer_id']),
              'customer_mobile': orderMap['customer_mobile'] ?? '',
              'customer_address': orderMap['customer_address'] ?? '',
              'items': itemsSummary.isNotEmpty ? itemsSummary : 'Garments',
              'items_summary': itemsSummary,
              'raw_items': items,
              'image_path': photoUrl,
              'order_date': orderMap['order_date'] ?? '',
              'delivery_date': orderMap['delivery_date'] ?? '',
              'status': status,
              'total_amount': total,
              'advance_amount': advance,
              'discount': discount,
              'remaining_amount': remaining,
              'special_instructions': orderMap['special_instructions'] ?? '',
              'payments': orderMap['payments'] ?? [],
              'ready_item_ids': readyItemIds,
              'delivered_item_ids': deliveredItemIds,
              'cloth_photos': orderMap['cloth_photos'] ?? [],
              'updated_at': orderMap['updated_at'] ?? '',
            };

            ordersSummaryList.add(summaryItem);

            if (remaining > 0) {
              pendingOrdersList.add(summaryItem);
              pendingBalance += remaining;
            }

            final upperStatus = status.toUpperCase();
            if (upperStatus == 'DELIVERED') {
              deliveredOrders++;
            } else if (upperStatus != 'CANCELLED') {
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
          final s = (o['status'] ?? '').toString().toUpperCase();
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
    } catch (e, stack) {
      debugPrint('IMPORT ERROR: $e\n$stack');
      // Restore safety snapshot so failure never destroys existing user data!
      await restoreSafetySnapshot();
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
  // SINGLE BACKUP TRACKING
  // -------------------------------------------------------------
  static const String _keyLastBackupTime = 'ht_last_backup_time';
  static const String _keyLastBackupSize = 'ht_last_backup_size';
  static const String _keyLastBackupPath = 'ht_last_backup_path';

  static Future<void> recordBackupSuccess({required String path, required int sizeBytes, String? timestamp}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowStr = timestamp ?? DateTime.now().toIso8601String();
      await prefs.setString(_keyLastBackupTime, nowStr);
      await prefs.setInt(_keyLastBackupSize, sizeBytes);
      await prefs.setString(_keyLastBackupPath, path);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getLastBackupRecord() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'timestamp': prefs.getString(_keyLastBackupTime),
        'sizeBytes': prefs.getInt(_keyLastBackupSize),
        'path': prefs.getString(_keyLastBackupPath),
      };
    } catch (_) {
      return {};
    }
  }

  static const String _keyCustomBackupFolder = 'ht_custom_backup_folder';

  static Future<void> setCustomBackupFolder(String? folderPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (folderPath == null || folderPath.isEmpty) {
        await prefs.remove(_keyCustomBackupFolder);
      } else {
        await prefs.setString(_keyCustomBackupFolder, folderPath);
      }
    } catch (_) {}
  }

  static Future<String?> getCustomBackupFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyCustomBackupFolder);
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------
  // CLEAR CACHE
  // -------------------------------------------------------------
  static Future<void> clearAll({bool enableOfflineMode = false}) async {
    try {
      // 0. Invalidate in-memory caches
      _memoryOrdersCache = null;
      _memoryCustomersCache = null;
      _memoryOrderDetailsCache.clear();
      _memoryMeasurementsCache.clear();
      _safetySnapshot = null;

      // 1. Delete all permanent disk JSON files & clear memory cache
      await clearAllDiskFiles();

      // 2. Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 3. Mark offline mode & clean fresh state
      if (enableOfflineMode) {
        await prefs.setBool(_keyOfflineMode, true);
      }
      await prefs.setBool(_keyCleanFreshState, true);

      // 4. Overwrite caches with explicit empty zero values
      await saveOrders([]);
      await saveCustomers([]);
      await savePendingOrders([]);
      await saveDeliveries({
        'deliveries': [],
        'today': [],
        'upcoming': [],
        'overdue': [],
      });
      final zeroStats = {
        'total_orders': 0,
        'active_orders': 0,
        'delivered_orders': 0,
        'urgent_orders': 0,
        'total_revenue': 0,
        'pending_balance': 0,
        'pending_payments': 0,
        'orders_today': 0,
        'deliveries_today': 0,
        'completed_today': 0,
        'recent_orders': <dynamic>[],
      };
      await saveDashboardStats(zeroStats);
    } catch (_) {}
  }
}


