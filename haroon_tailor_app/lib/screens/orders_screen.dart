import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../utils/phone_utils.dart';
import 'new_order_screen.dart';
import 'order_details_screen.dart';
import 'receipt_print_screen.dart';
import 'stitching_slip_print_screen.dart';

class DeliveryAlertInfo {
  final bool isOverdue;
  final int diffDays;
  final String label;
  final Color bgColor;
  final Color textColor;
  final Color borderColor;
  final IconData icon;

  const DeliveryAlertInfo({
    required this.isOverdue,
    required this.diffDays,
    required this.label,
    required this.bgColor,
    required this.textColor,
    required this.borderColor,
    required this.icon,
  });
}

class OrdersScreen extends StatefulWidget {
  final String initialStatus;
  const OrdersScreen({super.key, this.initialStatus = 'INCOMPLETE'});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  bool _isLoading = true;
  List<dynamic> _allOrders = [];
  List<dynamic> _filteredOrders = [];
  late String _selectedStatus;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    _loadOrders();
  }

  Future<void> _loadOrders({bool showLoading = true}) async {
    // 1. Instant local cache load (0 milliseconds delay!)
    final cached = await LocalStorageService.getCachedOrders();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _allOrders = cached;
        _applyFilter();
        _isLoading = false;
      });
    } else if (showLoading && _allOrders.isEmpty) {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh updates from server in background
    try {
      final orders = await ApiService.getAllOrders();
      if (mounted) {
        setState(() {
          _allOrders = orders;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_allOrders.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load orders: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  int get _incompleteCount => _allOrders.where((o) {
        final status = (o['status'] ?? '').toString();
        return status != 'DELIVERED' && status != 'STITCHING_COMPLETE' && status != 'CANCELLED';
      }).length;

  DeliveryAlertInfo? _getDeliveryAlert(Map<String, dynamic> o) {
    final status = (o['status'] ?? '').toString();
    if (status == 'DELIVERED' || status == 'CANCELLED' || status == 'STITCHING_COMPLETE') {
      return null;
    }

    final delivStr = o['delivery_date']?.toString();
    if (delivStr == null || delivStr.trim().isEmpty) {
      return null;
    }

    final dDate = DateTime.tryParse(delivStr.split('T')[0]);
    if (dDate == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(dDate.year, dDate.month, dDate.day);
    final diffDays = targetDate.difference(today).inDays;

    if (diffDays < 0) {
      final lateDays = -diffDays;
      return DeliveryAlertInfo(
        isOverdue: true,
        diffDays: diffDays,
        label: lateDays == 1 ? 'OVERDUE (1 Din Late)' : 'OVERDUE ($lateDays Din Late)',
        bgColor: const Color(0xFFFEE2E2),
        textColor: const Color(0xFFDC2626),
        borderColor: const Color(0xFFEF4444),
        icon: Icons.error_rounded,
      );
    } else if (diffDays == 0) {
      return const DeliveryAlertInfo(
        isOverdue: false,
        diffDays: 0,
        label: 'DELIVERY AAJ HAI (Today)',
        bgColor: Color(0xFFFEE2E2),
        textColor: Color(0xFFE11D48),
        borderColor: Color(0xFFF43F5E),
        icon: Icons.alarm,
      );
    } else if (diffDays == 1) {
      return const DeliveryAlertInfo(
        isOverdue: false,
        diffDays: 1,
        label: 'DELIVERY KAL HAI (1 Din Bacha)',
        bgColor: Color(0xFFFFF7ED),
        textColor: Color(0xFFEA580C),
        borderColor: Color(0xFFF97316),
        icon: Icons.warning_amber_rounded,
      );
    } else if (diffDays <= 3) {
      return DeliveryAlertInfo(
        isOverdue: false,
        diffDays: diffDays,
        label: '$diffDays Din Mein Delivery',
        bgColor: const Color(0xFFFEFCE8),
        textColor: const Color(0xFFCA8A04),
        borderColor: const Color(0xFFEAB308),
        icon: Icons.hourglass_top_rounded,
      );
    }

    return null;
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    _filteredOrders = _allOrders.where((o) {
      final status = (o['status'] ?? '').toString();
      bool matchesStatus = true;
      if (_selectedStatus == 'INCOMPLETE' || _selectedStatus == 'PENDING') {
        matchesStatus = status != 'DELIVERED' && status != 'STITCHING_COMPLETE' && status != 'CANCELLED';
      } else if (_selectedStatus == 'PARTIALLY_COMPLETE') {
        matchesStatus = status == 'PARTIALLY_COMPLETE';
      } else if (_selectedStatus == 'COMPLETE') {
        matchesStatus = status == 'STITCHING_COMPLETE';
      } else if (_selectedStatus == 'DELIVERED') {
        matchesStatus = status == 'DELIVERED';
      }

      if (!matchesStatus) return false;

      if (q.isNotEmpty) {
        final custName = (o['customer_name'] ?? '').toString().toLowerCase();
        final billNo = (o['order_number'] ?? '').toString().toLowerCase();
        final phone = (o['customer_mobile'] ?? '').toString().toLowerCase();
        return custName.contains(q) || billNo.contains(q) || phone.contains(q);
      }
      return true;
    }).toList();

    // Sort: Incomplete orders sorted by delivery date (nearest first, overdue on top)
    _filteredOrders.sort((a, b) {
      if (_selectedStatus == 'INCOMPLETE' || _selectedStatus == 'PENDING') {
        final dStrA = a['delivery_date']?.toString();
        final dStrB = b['delivery_date']?.toString();

        final dateA = (dStrA != null && dStrA.trim().isNotEmpty)
            ? DateTime.tryParse(dStrA.split('T')[0])
            : null;
        final dateB = (dStrB != null && dStrB.trim().isNotEmpty)
            ? DateTime.tryParse(dStrB.split('T')[0])
            : null;

        if (dateA == null && dateB == null) {
          return ((b['id'] ?? 0) as int).compareTo((a['id'] ?? 0) as int);
        }
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        final comp = dateA.compareTo(dateB);
        if (comp != 0) return comp;
        return ((b['id'] ?? 0) as int).compareTo((a['id'] ?? 0) as int);
      } else {
        return ((b['id'] ?? 0) as int).compareTo((a['id'] ?? 0) as int);
      }
    });
  }

  // 1. COMPLETE BUTTON WITH WHATSAPP CONFIRMATION (Point 2 - Website Flow)
  void _handleComplete(Map<String, dynamic> o) async {
    final orderId = o['id'] as int;
    final billNo = o['order_number'] ?? '#$orderId';
    bool sendWhatsapp = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: const Text('Mark Stitching Complete?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order $billNo ko Stitching Complete mark karein? Iska matlab kapde delivery ke liye tayyar hain.'),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send WhatsApp Notification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Website jaisa "Kapde tayyar hain" message customer ke WhatsApp par bheja jayega.', style: TextStyle(fontSize: 12)),
                    value: sendWhatsapp,
                    activeColor: const Color(0xFF25D366),
                    onChanged: (val) => setDlgState(() => sendWhatsapp = val ?? true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true) {
      try {
        final res = await ApiService.updateOrderStatus(
          orderId: orderId,
          status: 'STITCHING_COMPLETE',
          sendWhatsapp: sendWhatsapp,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order marked as Stitching Complete'), backgroundColor: Colors.green),
          );
        }

        // WhatsApp notification (exact website message)
        if (sendWhatsapp) {
          if (res['whatsapp_url'] != null) {
            await PhoneUtils.openBackendWhatsAppUrl(res['whatsapp_url'].toString());
          } else {
            final phone = (o['customer_mobile'] ?? '').toString();
            final custName = o['customer_name'] ?? 'Grahak';
            final shopSettings = await ApiService.getShopSettings();
            final shopName = shopSettings['shop_name'] ?? 'Haroon Tailor';
            final dynamic itemsRaw = o['items'];
            final String itemsStr = itemsRaw is String
                ? (itemsRaw.isNotEmpty ? itemsRaw : 'Kapde')
                : (itemsRaw is List && itemsRaw.isNotEmpty
                    ? itemsRaw.map((i) => '${i['quantity'] ?? 1} ${i['clothing_type'] ?? 'Kapde'}').join(', ')
                    : 'Kapde');

            final msg =
                '🎉 $custName! 🎉\n\n'
                'Aapka order #$billNo ($itemsStr) ab bilkul tayyar hai! Aap ise $shopName se le ja sakte hain.\n\n'
                'Kripya apni suvidha anusar dukan par aayein aur apne sile hue kapde prapt karein.\n\n'
                'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
                'Jald milenge!\n$shopName';

            await PhoneUtils.openWhatsApp(phone, msg);
          }
        }

        _loadOrders();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 2. PARTIAL BUTTON WITH CHECKBOXES MODAL (Point 1 - Website Flow)
  Future<void> _handlePartial(Map<String, dynamic> o) async {
    final orderId = o['id'] as int;
    final dynamic rawItemsVal = o['raw_items'];
    final dynamic itemsVal = o['items'];

    final List<Map<String, dynamic>> itemList = [];

    if (rawItemsVal is List && rawItemsVal.isNotEmpty) {
      for (var it in rawItemsVal) {
        if (it is Map) {
          itemList.add({
            'id': it['id'] ?? 0,
            'name': (it['name'] ?? 'Item').toString(),
            'is_ready': it['is_ready'] == true,
          });
        }
      }
    } else if (itemsVal is List && itemsVal.isNotEmpty) {
      for (var it in itemsVal) {
        if (it is Map) {
          itemList.add({
            'id': it['id'] ?? 0,
            'name': '${it['clothing_type'] ?? 'Custom Item'} (x${it['quantity'] ?? 1})',
            'is_ready': it['is_ready'] == true,
          });
        }
      }
    } else {
      // If raw_items was not in summary list, fetch full order details
      try {
        final details = await ApiService.getOrderDetails(orderId);
        final detItems = details['items'];
        if (detItems is List && detItems.isNotEmpty) {
          for (var it in detItems) {
            if (it is Map) {
              itemList.add({
                'id': it['id'] ?? 0,
                'name': '${it['clothing_type'] ?? 'Custom Item'} (x${it['quantity'] ?? 1})',
                'is_ready': it['is_ready'] == true,
              });
            }
          }
        }
      } catch (_) {}
    }

    if (itemList.isEmpty) {
      _quickStatusUpdate(orderId, 'PARTIALLY_COMPLETE');
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final allChecked = itemList.every((i) => i['is_ready'] == true);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.checklist, color: Color(0xFFD97706)),
                  SizedBox(width: 8),
                  Text('Partially Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Jo kapde sil kar tayyar hain unhe tick karein:',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itemList.length,
                        itemBuilder: (context, idx) {
                          final item = itemList[idx];
                          final isChecked = item['is_ready'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isChecked ? Colors.amber.shade50 : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isChecked ? Colors.amber.shade400 : Colors.grey.shade300,
                              ),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                item['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isChecked ? const Color(0xFF0F172A) : Colors.grey.shade800,
                                ),
                              ),
                              value: isChecked,
                              activeColor: const Color(0xFFD97706),
                              onChanged: (val) {
                                setModalState(() {
                                  item['is_ready'] = val ?? false;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final readyIds = itemList
                        .where((i) => i['is_ready'] == true)
                        .map((i) => int.tryParse(i['id'].toString()) ?? 0)
                        .where((id) => id > 0)
                        .toList();

                    try {
                      await ApiService.updateOrderStatus(
                        orderId: orderId,
                        status: allChecked ? 'STITCHING_COMPLETE' : 'PARTIALLY_COMPLETE',
                        readyItemIds: readyIds,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Items updated successfully!'), backgroundColor: Colors.green),
                        );
                      }
                      _loadOrders();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Update error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Save Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _quickStatusUpdate(int orderId, String newStatus) async {
    try {
      await ApiService.updateOrderStatus(orderId: orderId, status: newStatus);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to $newStatus'), backgroundColor: Colors.green),
        );
      }
      _loadOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteOrder(Map<String, dynamic> order) async {
    final orderId = order['id'] as int;
    final billNo = order['order_number'] ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Order $billNo?'),
        content: Text(
          'Kya aap sach me order $billNo delete karna chahte hain?\n\n'
          'Yeh bill number agle naye order ke liye dobara reuse hoga.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.deleteOrder(orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $billNo delete ho gaya.'), backgroundColor: Colors.red),
          );
        }
        _loadOrders();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete fail: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _shareWhatsAppReminder(Map<String, dynamic> order) async {
    final phone = (order['customer_mobile'] ?? '').toString();
    final billNo = order['order_number'] ?? '';
    final custName = order['customer_name'] ?? 'Grahak';
    final remaining = order['remaining_amount'] ?? 0;
    final shopSettings = await ApiService.getShopSettings();
    final shopName = shopSettings['shop_name'] ?? 'Haroon Tailor';

    final msg =
        '$custName,\n\n'
        'Yeh ek reminder hai ki aapke order $billNo ka Rs. $remaining baqaya hai. Kripya apni suvidha anusar ise jald se jald chuka dein.\n\n'
        'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
        'Dhanyawad!\n$shopName';

    PhoneUtils.openWhatsApp(phone, msg);
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Orders Directory', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_applyFilter),
              decoration: InputDecoration(
                hintText: 'Search order number, customer name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),

          // Status Filter Tabs
          // Status Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('INCOMPLETE', 'Incomplete Orders', count: _incompleteCount),
                _buildFilterChip('ALL', 'All Orders'),
                _buildFilterChip('PARTIALLY_COMPLETE', 'Partially Complete'),
                _buildFilterChip('COMPLETE', 'Complete'),
                _buildFilterChip('DELIVERED', 'Delivered'),
              ],
            ),
          ),

          // Informational sorting note when viewing Incomplete Orders
          if (_selectedStatus == 'INCOMPLETE' || _selectedStatus == 'PENDING')
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.sort_rounded, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Delivery date nazdeek wale orders pehle dikh rahe hain (Alerts: ≤ 3 din)',
                      style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Koi orders nahi mile',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredOrders.length,
                          itemBuilder: (context, idx) {
                            final o = _filteredOrders[idx];
                            final orderId = o['id'] as int;
                            final billNo = o['order_number'] ?? 'Bill-#$orderId';
                            final custName = o['customer_name'] ?? 'Walk-in';
                            final phone = (o['customer_mobile'] ?? '').toString();
                            final status = (o['status'] ?? 'NEW').toString();
                            final total = o['total_amount'] ?? 0;
                            final remaining = o['remaining_amount'] ?? 0;
                            final alert = _getDeliveryAlert(o);

                            return Card(
                              elevation: alert != null ? 2 : 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: alert != null ? alert.borderColor.withValues(alpha: 0.6) : Colors.grey.shade200,
                                  width: alert != null ? 1.5 : 1.0,
                                ),
                              ),
                              color: alert != null ? alert.bgColor.withValues(alpha: 0.25) : Colors.white,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderDetailsScreen(
                                        orderId: orderId,
                                        onOrderUpdated: _loadOrders,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // URGENT ALERT BANNER (If delivery date is <= 3 days or overdue)
                                      if (alert != null)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: alert.bgColor,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: alert.borderColor.withValues(alpha: 0.6)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(alert.icon, size: 14, color: alert.textColor),
                                              const SizedBox(width: 6),
                                              Text(
                                                alert.label,
                                                style: TextStyle(
                                                  color: alert.textColor,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            billNo,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(status).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status.replaceAll('_', ' '),
                                              style: TextStyle(
                                                color: _getStatusColor(status),
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        custName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      if (phone.isNotEmpty)
                                        Text(phone, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                      if (o['delivery_date'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.event_outlined,
                                                size: 14,
                                                color: alert != null ? alert.textColor : Colors.grey.shade600,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Delivery: ${o['delivery_date'].toString().split('T')[0]}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: alert != null ? FontWeight.bold : FontWeight.normal,
                                                  color: alert != null ? alert.textColor : Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const Divider(height: 18),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Total: ${currency.format(total)}',
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                              if (remaining > 0)
                                                Text('Due: ${currency.format(remaining)}',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13))
                                              else
                                                const Text('Paid',
                                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                                            ],
                                          ),
                                          // ACTION BUTTONS (Complete, Partial, Print, WhatsApp)
                                          Row(
                                            children: [
                                              // WhatsApp Reminder
                                              IconButton(
                                                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                                                tooltip: 'Send WhatsApp Reminder',
                                                onPressed: () => _shareWhatsAppReminder(o),
                                              ),

                                              // Partial Button with Checkbox modal (Point 1)
                                              if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: OutlinedButton(
                                                    style: OutlinedButton.styleFrom(
                                                      side: const BorderSide(color: Color(0xFFD97706)),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _handlePartial(o),
                                                    child: const Text('Partial',
                                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                                                  ),
                                                ),

                                              // Complete Button with WhatsApp toggle (Point 2)
                                              if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF0F172A),
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      minimumSize: Size.zero,
                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                    ),
                                                    onPressed: () => _handleComplete(o),
                                                    child: const Text('Complete',
                                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                                  ),
                                                ),

                                              // More actions menu (Print Bill, Stitching Slip, Edit, Delete)
                                              PopupMenuButton<String>(
                                                icon: const Icon(Icons.more_vert, size: 20, color: Colors.blueGrey),
                                                onSelected: (val) {
                                                  if (val == 'receipt') {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => ReceiptPrintScreen(orderId: orderId, initialOrder: o),
                                                      ),
                                                    );
                                                  } else if (val == 'slip') {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => StitchingSlipPrintScreen(orderId: orderId, initialOrder: o),
                                                      ),
                                                    );
                                                  } else if (val == 'edit') {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => NewOrderScreen(
                                                          editOrder: o,
                                                          onOrderUpdated: _loadOrders,
                                                        ),
                                                      ),
                                                    );
                                                  } else if (val == 'delete') {
                                                    _deleteOrder(o);
                                                  }
                                                },
                                                itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                    value: 'receipt',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.receipt, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Print Customer Bill'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'slip',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.content_cut, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Print Stitching Slip'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'edit',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.edit, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Edit Order'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete, color: Colors.red, size: 18),
                                                        SizedBox(width: 8),
                                                        Text('Delete Order', style: TextStyle(color: Colors.red)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, {int? count}) {
    final isSelected = _selectedStatus == value;
    final displayLabel = count != null && count > 0 ? '$label ($count)' : label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: value == 'INCOMPLETE'
            ? Icon(
                Icons.schedule,
                size: 16,
                color: isSelected ? Colors.amberAccent : const Color(0xFFD97706),
              )
            : null,
        label: Text(displayLabel),
        selected: isSelected,
        selectedColor: const Color(0xFF0F172A),
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _selectedStatus = value;
              _applyFilter();
            });
          }
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'DELIVERED':
        return Colors.green;
      case 'STITCHING_COMPLETE':
        return Colors.blue;
      case 'PARTIALLY_COMPLETE':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }
}
