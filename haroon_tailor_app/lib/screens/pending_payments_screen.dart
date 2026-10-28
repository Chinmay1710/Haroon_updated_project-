import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
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
  String _selectedTab = 'ALL'; // 'ALL', 'DELIVERED', 'UNDELIVERED'
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

  Future<void> _loadPendingOrders({bool showLoading = true}) async {
    if (showLoading && _allPending.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      // 1. Instant local computation directly from local orders
      final localPending = await LocalStorageService.computePendingOrdersFromOrders();
      final cachedAllOrders = await LocalStorageService.getCachedOrders();
      final Map<String, String> statusMap = {};
      if (cachedAllOrders != null) {
        for (var o in cachedAllOrders) {
          if (o is Map && o['id'] != null) {
            statusMap[o['id'].toString()] = (o['status'] ?? 'NEW').toString();
          }
        }
      }

      final list = List<dynamic>.from(localPending);
      for (var o in list) {
        if (o is Map && o['id'] != null) {
          final idKey = o['id'].toString();
          if (statusMap.containsKey(idKey)) {
            o['status'] = statusMap[idKey];
          } else if (o['status'] == null) {
            o['status'] = 'NEW';
          }
        }
      }

      if (mounted) {
        setState(() {
          _allPending = list;
          _filterList();
          _isLoading = false;
        });
      }

      // 2. Background sync only if online mode is enabled
      if (!await LocalStorageService.isOfflineMode()) {
        try {
          final cloudData = await ApiService.getPendingOrders();
          if (cloudData.isNotEmpty && mounted) {
            final cloudList = List<dynamic>.from(cloudData);
            for (var o in cloudList) {
              if (o is Map && o['id'] != null) {
                final idKey = o['id'].toString();
                if (statusMap.containsKey(idKey)) {
                  o['status'] = statusMap[idKey];
                } else if (o['status'] == null) {
                  o['status'] = 'NEW';
                }
              }
            }
            setState(() {
              _allPending = cloudList;
              _filterList();
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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


  List<dynamic> get _filteredDeliveredOrders => _filteredPending.where((o) {
        final status = (o['status'] ?? '').toString().toUpperCase();
        return status == 'DELIVERED';
      }).toList();

  List<dynamic> get _filteredUndeliveredOrders => _filteredPending.where((o) {
        final status = (o['status'] ?? '').toString().toUpperCase();
        return status != 'DELIVERED';
      }).toList();

  double _calculateTotal(List<dynamic> orders) {
    double sum = 0.0;
    for (var o in orders) {
      sum += (o['remaining_amount'] as num?)?.toDouble() ??
          double.tryParse((o['remaining_amount'] ?? 0).toString()) ??
          0.0;
    }
    return sum;
  }

  double get _totalDue => _calculateTotal(_filteredPending);
  double get _deliveredFilteredTotal => _calculateTotal(_filteredDeliveredOrders);
  double get _undeliveredFilteredTotal => _calculateTotal(_filteredUndeliveredOrders);

  void _sendReminder(Map<String, dynamic> order) async {
    final phone = (order['customer_mobile'] ?? '').toString();
    final billNo = order['order_number'] ?? '';
    final custName = order['customer_name'] ?? '';
    final remaining = order['remaining_amount'] ?? 0;

    final msg = await PhoneUtils.buildMessage(
      templateKey: 'payment_reminder',
      customerName: custName,
      orderNumber: billNo,
      balanceAmount: remaining is num ? remaining : (num.tryParse(remaining.toString()) ?? 0),
    );

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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
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
                      if (amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kripya 0 se zyada payment rashi bharein!'), backgroundColor: Colors.orange),
                        );
                        return;
                      }
                      if (amt > remaining) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Payment baqaya rashi (₹${remaining.toStringAsFixed(0)}) se zyada nahi ho sakta!'), backgroundColor: Colors.orange),
                        );
                        return;
                      }
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

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required double totalAmount,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: iconColor),
                    ),
                    Text(
                      currency.format(totalAmount),
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: iconColor),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                    Text(
                      '$count orders',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: iconColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> o) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final billNo = o['order_number'] ?? 'Bill-#${o['id']}';
    final custName = o['customer_name'] ?? 'Unknown';
    final phone = (o['customer_mobile'] ?? '').toString();
    final remaining = double.tryParse((o['remaining_amount'] ?? 0).toString()) ?? 0.0;
    final total = double.tryParse((o['total_amount'] ?? 0).toString()) ?? 0.0;
    final status = (o['status'] ?? 'NEW').toString();
    final isDelivered = status == 'DELIVERED';
    final delivDate = o['delivery_date'] != null && o['delivery_date'].toString().isNotEmpty
        ? o['delivery_date'].toString().split('T')[0]
        : null;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDelivered ? const Color(0xFFC084FC).withValues(alpha: 0.5) : Colors.grey.shade200,
          width: isDelivered ? 1.4 : 1.0,
        ),
      ),
      color: isDelivered ? const Color(0xFFFAF5FF) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          int ordId = int.tryParse((o['id'] ?? '').toString()) ?? 0;
          if (ordId <= 0) {
            final bDigits = RegExp(r'\d+').allMatches((o['order_number'] ?? '').toString()).lastOrNull?.group(0);
            if (bDigits != null) ordId = int.tryParse(bDigits) ?? 0;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderDetailsScreen(
                orderId: ordId > 0 ? ordId : (o['id'] is int ? o['id'] : 0),
                onOrderUpdated: _loadPendingOrders,
              ),
            ),
          );
          _loadPendingOrders();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Status Badge Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDelivered ? const Color(0xFFEDE9FE) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDelivered ? const Color(0xFF8B5CF6).withValues(alpha: 0.5) : const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDelivered ? Icons.inventory_2 : Icons.hourglass_top_rounded,
                          size: 13,
                          color: isDelivered ? const Color(0xFF6D28D9) : const Color(0xFFB45309),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isDelivered ? 'Delivery Ho Gayi' : (status == 'STITCHING_COMPLETE' ? 'Silai Ready • Delivery Baki' : 'Delivery Baki Hai'),
                          style: TextStyle(
                            color: isDelivered ? const Color(0xFF6D28D9) : const Color(0xFFB45309),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Remaining Due Highlight
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Baqaya (Due):', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      Text(
                        currency.format(remaining),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Customer & Bill
              Text(
                custName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(billNo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF2563EB))),
                  if (phone.isNotEmpty) ...[
                    Text(' • $phone', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ],
              ),

              if (delivDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, size: 13, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Delivery Date: $delivDate',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),

              const Divider(height: 18),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Bill: ${currency.format(total)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  ),
                  Row(
                    children: [
                      // WhatsApp Reminder button
                      IconButton(
                        icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 22),
                        tooltip: isDelivered ? 'Delivery Ho Gayi Reminder' : 'Delivery Baki Reminder',
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
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    final deliveredList = _filteredDeliveredOrders;
    final undeliveredList = _filteredUndeliveredOrders;

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
          // 1. Total Due Header Banner with 2-Section Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF0F172A),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedTab == 'DELIVERED'
                              ? 'Delivery Ho Gayi • Pending'
                              : _selectedTab == 'UNDELIVERED'
                                  ? 'Delivery Baki • Pending'
                                  : 'Total Pending Balance',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currency.format(_selectedTab == 'DELIVERED'
                              ? _deliveredFilteredTotal
                              : _selectedTab == 'UNDELIVERED'
                                  ? _undeliveredFilteredTotal
                                  : _totalDue),
                          style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 24),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_selectedTab == 'DELIVERED' ? deliveredList.length : _selectedTab == 'UNDELIVERED' ? undeliveredList.length : _filteredPending.length} Orders Due',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Section 1 & Section 2 Quick KPI Cards
                Row(
                  children: [
                    // Section 1: Delivery Ho Gayi
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = _selectedTab == 'DELIVERED' ? 'ALL' : 'DELIVERED'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 'DELIVERED'
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedTab == 'DELIVERED' ? const Color(0xFFA78BFA) : Colors.white12,
                              width: _selectedTab == 'DELIVERED' ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.inventory_2, size: 14, color: Color(0xFFA78BFA)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Delivery Ho Gayi',
                                      style: TextStyle(color: Colors.purple.shade100, fontSize: 11, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(currency.format(_deliveredFilteredTotal),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('${deliveredList.length} orders pending',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Section 2: Delivery Baki Hai
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _selectedTab = _selectedTab == 'UNDELIVERED' ? 'ALL' : 'UNDELIVERED'),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 'UNDELIVERED'
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedTab == 'UNDELIVERED' ? const Color(0xFFFBBF24) : Colors.white12,
                              width: _selectedTab == 'UNDELIVERED' ? 1.5 : 1.0,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFFFBBF24)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Delivery Baki Hai',
                                      style: TextStyle(color: Colors.amber.shade100, fontSize: 11, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(currency.format(_undeliveredFilteredTotal),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('${undeliveredList.length} orders pending',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_filterList),
              decoration: InputDecoration(
                hintText: 'Search customer name, bill no, phone...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
              ),
            ),
          ),

          // 3. Section Filter Chips (Sabhi / Delivery Ho Gayi / Delivery Baki)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('Sabhi (${_filteredPending.length})'),
                  selected: _selectedTab == 'ALL',
                  selectedColor: const Color(0xFF0F172A),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _selectedTab == 'ALL' ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _selectedTab = 'ALL'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: Icon(
                    Icons.inventory_2,
                    size: 14,
                    color: _selectedTab == 'DELIVERED' ? Colors.white : const Color(0xFF6D28D9),
                  ),
                  label: Text('Delivery Ho Gayi (${deliveredList.length})'),
                  selected: _selectedTab == 'DELIVERED',
                  selectedColor: const Color(0xFF6D28D9),
                  backgroundColor: const Color(0xFFEDE9FE),
                  labelStyle: TextStyle(
                    color: _selectedTab == 'DELIVERED' ? Colors.white : const Color(0xFF6D28D9),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _selectedTab = 'DELIVERED'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: Icon(
                    Icons.hourglass_top_rounded,
                    size: 14,
                    color: _selectedTab == 'UNDELIVERED' ? Colors.white : const Color(0xFFB45309),
                  ),
                  label: Text('Delivery Baki Hai (${undeliveredList.length})'),
                  selected: _selectedTab == 'UNDELIVERED',
                  selectedColor: const Color(0xFFD97706),
                  backgroundColor: const Color(0xFFFEF3C7),
                  labelStyle: TextStyle(
                    color: _selectedTab == 'UNDELIVERED' ? Colors.white : const Color(0xFFB45309),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() => _selectedTab = 'UNDELIVERED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // 4. Orders List with 2 Sections
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPending.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchCtrl.text.trim().isNotEmpty ? Icons.search_off : Icons.check_circle_outline,
                              size: 56,
                              color: _searchCtrl.text.trim().isNotEmpty ? Colors.grey.shade400 : Colors.green.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchCtrl.text.trim().isNotEmpty ? 'Koi order nahi mila' : 'Koi Pending Payment nahi hai!',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _searchCtrl.text.trim().isNotEmpty
                                  ? 'Is search query ke sath koi pending payment match nahi hua.'
                                  : 'Sabhi grahak ka hisaab clear hai.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPendingOrders,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          children: [
                            // SECTION 1: DELIVERY HO GAYI (DELIVERED)
                            if (_selectedTab == 'ALL' || _selectedTab == 'DELIVERED') ...[
                              if (deliveredList.isNotEmpty) ...[
                                _buildSectionHeader(
                                  icon: Icons.inventory_2,
                                  title: 'Delivery Ho Gayi • Payment Pending',
                                  subtitle: 'Grahak ko kapde de diye hain, baqaya rashi lena baki hai',
                                  count: deliveredList.length,
                                  totalAmount: _calculateTotal(deliveredList),
                                  iconColor: const Color(0xFF6D28D9),
                                  bgColor: const Color(0xFFF5F3FF),
                                  borderColor: const Color(0xFFDDD6FE),
                                ),
                                ...deliveredList.map((o) => _buildOrderCard(Map<String, dynamic>.from(o))),
                              ] else if (_selectedTab == 'DELIVERED') ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text(
                                      'Delivery ho chuke orders me koi pending payment nahi hai!',
                                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ),
                              ],
                            ],

                            // SECTION 2: DELIVERY BAKI HAI (UNDELIVERED)
                            if (_selectedTab == 'ALL' || _selectedTab == 'UNDELIVERED') ...[
                              if (undeliveredList.isNotEmpty) ...[
                                _buildSectionHeader(
                                  icon: Icons.hourglass_top_rounded,
                                  title: 'Delivery Baki Hai • Payment Pending',
                                  subtitle: 'Kapde silai ya ready hain, delivery ke waqt payment lena hai',
                                  count: undeliveredList.length,
                                  totalAmount: _calculateTotal(undeliveredList),
                                  iconColor: const Color(0xFFB45309),
                                  bgColor: const Color(0xFFFFFBEB),
                                  borderColor: const Color(0xFFFDE68A),
                                ),
                                ...undeliveredList.map((o) => _buildOrderCard(Map<String, dynamic>.from(o))),
                              ] else if (_selectedTab == 'UNDELIVERED') ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text(
                                      'Delivery baki wale orders me koi pending payment nahi hai!',
                                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
