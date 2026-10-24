import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../utils/phone_utils.dart';
import 'order_details_screen.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => DeliveriesScreenState();
}

class DeliveriesScreenState extends State<DeliveriesScreen> {
  bool _isLoading = true;
  List<dynamic> _deliveries = [];
  List<dynamic> _filteredDeliveries = [];
  final TextEditingController _searchCtrl = TextEditingController();

  void reloadDeliveries() {
    _loadDeliveries();
  }

  @override
  void initState() {
    super.initState();
    _loadDeliveries();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeliveries({bool showLoading = true}) async {
    // 1. Instant local cache load (0 milliseconds delay!)
    final cached = await LocalStorageService.getCachedDeliveries();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _deliveries = cached['deliveries'] ?? [];
        _filterList();
        _isLoading = false;
      });
    } else if (showLoading && _deliveries.isEmpty) {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh updates from server in background
    try {
      final data = await ApiService.getDeliveriesDashboard();
      if (mounted) {
        setState(() {
          _deliveries = data['deliveries'] ?? [];
          _filterList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_deliveries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load deliveries: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _filterList() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredDeliveries = List.from(_deliveries);
    } else {
      _filteredDeliveries = _deliveries.where((d) {
        final custName = (d['customer_name'] ?? '').toString().toLowerCase();
        final orderNum = (d['order_number'] ?? '').toString().toLowerCase();
        final itemsStr = _formatItems(d).toLowerCase();
        return custName.contains(q) || orderNum.contains(q) || itemsStr.contains(q);
      }).toList();
    }
  }

  String _formatItems(Map<String, dynamic> d) {
    final summary = (d['items_summary'] ?? '').toString().trim();
    if (summary.isNotEmpty && !summary.startsWith('[') && !summary.startsWith('{')) {
      return summary;
    }
    final rawItems = d['items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return rawItems.map((it) {
        if (it is Map) {
          final qty = it['quantity'] ?? 1;
          final type = it['clothing_type'] ?? it['item_name'] ?? 'Kapda';
          return '$qty $type';
        }
        return it.toString();
      }).join(', ');
    }
    if (rawItems is String && rawItems.isNotEmpty && !rawItems.startsWith('[') && !rawItems.startsWith('{')) {
      return rawItems;
    }
    return 'Kapde';
  }

  Future<void> _handleDelivery(Map<String, dynamic> d) async {
    final orderId = int.tryParse((d['id'] ?? '').toString()) ?? 0;
    final custName = d['customer_name'] ?? 'Unknown';
    final billNo = d['order_number'] ?? '';
    final remaining = double.tryParse((d['remaining_amount'] ?? 0).toString()) ?? 0.0;
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (remaining > 0) {
      final amtCtrl = TextEditingController(text: remaining.toStringAsFixed(0));
      String payMethod = 'Cash';

      try {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) {
            return StatefulBuilder(
              builder: (ctx, setSheetState) {
                final enteredAmt = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
                final newRemaining = (remaining - enteredAmt) < 0 ? 0.0 : (remaining - enteredAmt);

                return Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payments, color: Colors.red, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Deliver $billNo - $custName',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('Baqaya (Due): ${currency.format(remaining)}',
                                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        const Text('Grahak ne kitna payment diya?', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: amtCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                          ],
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            prefixText: '₹ ',
                            labelText: 'Payment Amount',
                            hintText: 'Jaise: 300',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        if (enteredAmt > 0 && newRemaining > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Baki bachega: ₹${newRemaining.toStringAsFixed(0)} (Pending Payments me rahega)',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ] else if (enteredAmt >= remaining && remaining > 0) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'Poora payment jama ho jayega (Fully Paid)',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: payMethod,
                          decoration: InputDecoration(
                            labelText: 'Payment Method',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                            DropdownMenuItem(value: 'UPI', child: Text('UPI / QR')),
                            DropdownMenuItem(value: 'Card', child: Text('Card')),
                          ],
                          onChanged: (val) {
                            if (val != null) setSheetState(() => payMethod = val);
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  // Deliver without collecting now
                                  await _markDeliveredApi(orderId, remaining);
                                },
                                child: const Text('Bina Payment Deliver',
                                    style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () async {
                                  final amt = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
                                  if (amt <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Kripya 0 se zyada payment rashi bharein!'), backgroundColor: Colors.orange),
                                    );
                                    return;
                                  }
                                  if (amt > remaining) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Payment baqaya amount (${currency.format(remaining)}) se zyada nahi ho sakta!'), backgroundColor: Colors.orange),
                                    );
                                    return;
                                  }
                                  Navigator.pop(ctx);
                                  try {
                                    await ApiService.createPayment(
                                      orderId: orderId,
                                      amount: amt,
                                      paymentMethod: payMethod,
                                      sendWhatsapp: true,
                                    );
                                  } catch (_) {}
                                  final remDue = (remaining - amt) < 0 ? 0.0 : (remaining - amt);
                                  await _markDeliveredApi(orderId, remDue);
                                },
                                child: const Text('Payment Jama & Deliver',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      } finally {
        amtCtrl.dispose();
      }
    } else {
      // Fully paid, direct confirm
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Delivery'),
          content: Text('Order "$billNo" for $custName deliver mark karein?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Deliver', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _markDeliveredApi(orderId, 0.0);
      }
    }
  }

  Future<void> _markDeliveredApi(int orderId, [double? remainingDue]) async {
    try {
      await ApiService.updateOrderStatus(
        orderId: orderId,
        status: 'DELIVERED',
        sendWhatsapp: true,
      );
      _loadDeliveries();
      if (mounted) {
        if (remainingDue != null && remainingDue > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deliver ho gaya! Baqaya ₹${remainingDue.toStringAsFixed(0)} Pending Payments me jod diya gaya hai.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delivery marked as DELIVERED!'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Deliveries (Ready & Due)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadDeliveries),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_filterList),
              decoration: InputDecoration(
                hintText: 'Search deliveries by customer, bill no...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _filteredDeliveries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('No pending deliveries!', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDeliveries,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredDeliveries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final d = Map<String, dynamic>.from(_filteredDeliveries[index]);
                            final orderId = int.tryParse((d['id'] ?? '').toString()) ?? 0;
                            final remaining = double.tryParse((d['remaining_amount'] ?? 0).toString()) ?? 0.0;
                            final isDelivered = d['status'] == 'DELIVERED';
                            final billNo = d['order_number'] ?? '';
                            final custName = d['customer_name'] ?? 'Unknown';
                            final itemsStr = _formatItems(d);
                            final phone = (d['customer_mobile'] ?? '').toString();

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  // Open complete order details (Point 8)
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderDetailsScreen(
                                        orderId: orderId,
                                        onOrderUpdated: _loadDeliveries,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
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
                                              color: (isDelivered ? Colors.green : Colors.blue).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              (d['status'] ?? '').toString().replaceAll('_', ' '),
                                              style: TextStyle(
                                                color: isDelivered ? Colors.green : Colors.blue,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        custName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Item: $itemsStr', style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                                      const SizedBox(height: 4),
                                      if (d['delivery_date'] != null)
                                        Text(
                                          'Due: ${d['delivery_date'].toString().split('T')[0]}',
                                          style: const TextStyle(fontSize: 13, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                                        ),
                                      const Divider(height: 20),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (remaining > 0)
                                                Text('Baqaya (Due): ${currency.format(remaining)}',
                                                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))
                                              else
                                                const Text('Fully Paid',
                                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
                                                tooltip: 'WhatsApp Reminder',
                                                onPressed: () async {
                                                  final msg = await PhoneUtils.buildMessage(
                                                    templateKey: 'order_ready',
                                                    customerName: custName,
                                                    orderNumber: billNo,
                                                    balanceAmount: remaining,
                                                  );
                                                  PhoneUtils.openWhatsApp(phone, msg);
                                                },
                                              ),
                                              if (!isDelivered)
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF059669),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                  ),
                                                  icon: const Icon(Icons.check, size: 16, color: Colors.white),
                                                  label: const Text('Deliver',
                                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  onPressed: () => _handleDelivery(d),
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
}
