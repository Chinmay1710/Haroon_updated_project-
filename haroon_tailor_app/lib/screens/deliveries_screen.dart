import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import 'order_details_screen.dart';

class DeliveriesScreen extends StatefulWidget {
  const DeliveriesScreen({super.key});

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  bool _isLoading = true;
  List<dynamic> _deliveries = [];
  List<dynamic> _filteredDeliveries = [];
  final TextEditingController _searchCtrl = TextEditingController();

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

  Future<void> _loadDeliveries() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getDeliveriesDashboard();
      setState(() {
        _deliveries = data['deliveries'] ?? [];
        _filterList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load deliveries: $e'), backgroundColor: Colors.red),
        );
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
        final items = (d['items'] ?? '').toString().toLowerCase();
        return custName.contains(q) || orderNum.contains(q) || items.contains(q);
      }).toList();
    }
  }

  Future<void> _handleDelivery(Map<String, dynamic> d) async {
    final orderId = d['id'] as int;
    final custName = d['customer_name'] ?? 'Unknown';
    final billNo = d['order_number'] ?? '';
    final remaining = double.tryParse((d['remaining_amount'] ?? 0).toString()) ?? 0.0;
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (remaining > 0) {
      // Ask about remaining payment (Point 5)
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final amtCtrl = TextEditingController(text: remaining.toStringAsFixed(0));
          String payMethod = 'Cash';

          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
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
                    const Text('Grahak ne baqaya payment diya?', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amtCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        labelText: 'Payment Amount',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
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
                              await _markDeliveredApi(orderId);
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
                              Navigator.pop(ctx);
                              if (amt > 0) {
                                try {
                                  await ApiService.createPayment(
                                    orderId: orderId,
                                    amount: amt,
                                    paymentMethod: payMethod,
                                    sendWhatsapp: true,
                                  );
                                } catch (_) {}
                              }
                              await _markDeliveredApi(orderId);
                            },
                            child: const Text('Payment Jama & Deliver',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
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
        await _markDeliveredApi(orderId);
      }
    }
  }

  Future<void> _markDeliveredApi(int orderId) async {
    try {
      await ApiService.updateOrderStatus(
        orderId: orderId,
        status: 'DELIVERED',
        sendWhatsapp: true,
      );
      _loadDeliveries();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery marked as DELIVERED!'), backgroundColor: Colors.green),
        );
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
                            final orderId = d['id'] as int;
                            final remaining = double.tryParse((d['remaining_amount'] ?? 0).toString()) ?? 0.0;
                            final isDelivered = d['status'] == 'DELIVERED';
                            final billNo = d['order_number'] ?? '';
                            final custName = d['customer_name'] ?? 'Unknown';
                            final items = d['items'] ?? 'Garment';
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
                                      Text('Item: $items', style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
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
                                                onPressed: () {
                                                  final msg =
                                                      'Assalam-o-Alaikum $custName ji,\n'
                                                      'Haroon Tailor se aapka order ($billNo) taiyar hai.\n'
                                                      'Baqaya Rakam: ₹$remaining\n'
                                                      'Shukriya!';
                                                  PhoneUtils.openWhatsApp(phone: phone, message: msg);
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
