import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import 'order_details_screen.dart';

class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({super.key});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  bool _isLoading = true;
  List<dynamic> _allPending = [];
  List<dynamic> _filteredPending = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPendingOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPendingOrders() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getPendingOrders();
      if (!mounted) return;
      setState(() {
        _allPending = data;
        _filterList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load pending payments: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _filterList() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filteredPending = List.from(_allPending);
    } else {
      _filteredPending = _allPending.where((o) {
        final custName = (o['customer_name'] ?? '').toString().toLowerCase();
        final billNo = (o['order_number'] ?? '').toString().toLowerCase();
        final phone = (o['customer_mobile'] ?? '').toString().toLowerCase();
        return custName.contains(q) || billNo.contains(q) || phone.contains(q);
      }).toList();
    }
  }

  double get _totalDue {
    double sum = 0.0;
    for (var o in _filteredPending) {
      sum += double.tryParse((o['remaining_amount'] ?? 0).toString()) ?? 0.0;
    }
    return sum;
  }

  void _sendReminder(Map<String, dynamic> order) {
    final phone = (order['customer_mobile'] ?? '').toString();
    final billNo = order['order_number'] ?? '';
    final custName = order['customer_name'] ?? '';
    final remaining = order['remaining_amount'] ?? 0;

    final msg =
        'Assalam-o-Alaikum $custName ji,\n'
        'Haroon Tailor se vinamra anurodh:\n'
        'Aapka order ($billNo) ka baqaya bhugtan ₹$remaining pending hai.\n'
        'Kripya suvidhanusar jama karein. Shukriya!';

    PhoneUtils.openWhatsApp(phone, msg);
  }

  void _collectPayment(Map<String, dynamic> order) {
    final orderId = order['id'] as int;
    final billNo = order['order_number'] ?? '';
    final remaining = double.tryParse((order['remaining_amount'] ?? 0).toString()) ?? 0.0;

    final amtCtrl = TextEditingController(text: remaining.toStringAsFixed(0));
    String payMethod = 'Cash';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
                  Text('Collect Payment - $billNo',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                  const SizedBox(height: 4),
                  Text('Customer: ${order['customer_name'] ?? 'Unknown'}',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const Divider(height: 24),
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      labelText: 'Payment Rakam (Amount)',
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
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final amt = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
                      if (amt <= 0) return;
                      Navigator.pop(ctx);

                      try {
                        final res = await ApiService.createPayment(
                          orderId: orderId,
                          amount: amt,
                          paymentMethod: payMethod,
                          sendWhatsapp: true,
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Payment ₹$amt safaltapoorvak jama ho gaya!'), backgroundColor: Colors.green),
                          );
                        }

                        // Open receipt WhatsApp if returned
                        if (res['whatsapp_url'] != null) {
                          await PhoneUtils.openBackendWhatsAppUrl(res['whatsapp_url'].toString());
                        }

                        _loadPendingOrders();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Payment jama nahi hua: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: const Text('PAYMENT JAMA KAREIN',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Pending Payments', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadPendingOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // Total Due Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Pending Balance', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(currency.format(_totalDue),
                        style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 22)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${_filteredPending.length} Orders Due',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_filterList),
              decoration: InputDecoration(
                hintText: 'Search by customer, bill no, mobile...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPending.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 56, color: Colors.green.shade400),
                            const SizedBox(height: 12),
                            const Text('Koi Pending Payment nahi hai!',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                            const SizedBox(height: 4),
                            Text('Sabhi grahak ka hisaab clear hai.', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPendingOrders,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          itemCount: _filteredPending.length,
                          itemBuilder: (context, idx) {
                            final o = Map<String, dynamic>.from(_filteredPending[idx]);
                            final billNo = o['order_number'] ?? 'Bill-#${o['id']}';
                            final custName = o['customer_name'] ?? 'Unknown';
                            final phone = (o['customer_mobile'] ?? '').toString();
                            final remaining = double.tryParse((o['remaining_amount'] ?? 0).toString()) ?? 0.0;
                            final total = double.tryParse((o['total_amount'] ?? 0).toString()) ?? 0.0;

                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Colors.grey.shade200),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => OrderDetailsScreen(
                                        orderId: o['id'],
                                        onOrderUpdated: _loadPendingOrders,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(custName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                                              Text('$billNo • $phone',
                                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('Baqaya (Due):', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                              Text(currency.format(remaining),
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.red)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 18),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Total Bill: ${currency.format(total)}',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                          Row(
                                            children: [
                                              // WhatsApp Reminder button
                                              IconButton(
                                                icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
                                                tooltip: 'Send WhatsApp Reminder',
                                                onPressed: () => _sendReminder(o),
                                              ),
                                              const SizedBox(width: 4),
                                              // Collect payment button
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.green.shade700,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.payment, size: 16, color: Colors.white),
                                                label: const Text('Jama Karein',
                                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                                onPressed: () => _collectPayment(o),
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
