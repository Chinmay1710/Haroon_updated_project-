import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import 'new_order_screen.dart';
import 'order_details_screen.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final int customerId;

  const CustomerDetailsScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _customerData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCustomerDetails();
  }

  Future<void> _loadCustomerDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getCustomerDetails(widget.customerId);
      setState(() {
        _customerData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Grahak Details', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _customerData == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Grahak Details', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage ?? 'Customer details not found', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadCustomerDetails, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final c = Map<String, dynamic>.from(_customerData!['customer'] ?? {});
    final orders = List<dynamic>.from(_customerData!['orders'] ?? []);
    final profiles = List<dynamic>.from(_customerData!['profiles'] ?? []);

    final custName = c['name'] ?? 'Unknown Customer';
    final custMobile = (c['mobile'] ?? '').toString();
    final custAddress = (c['address'] ?? '').toString();
    final custNotes = (c['notes'] ?? '').toString();

    double totalBalance = 0.0;
    for (var o in orders) {
      totalBalance += double.tryParse((o['remaining_amount'] ?? 0).toString()) ?? 0.0;
    }

    final customerObj = Customer(
      id: widget.customerId,
      name: custName,
      mobile: custMobile,
      address: custAddress,
      notes: custNotes,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(custName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCustomerDetails,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. CUSTOMER INFO CARD
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: const Color(0xFF0F172A).withOpacity(0.1),
                          child: Text(
                            custName.isNotEmpty ? custName[0].toUpperCase() : 'C',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const SizedBox(height: 2),
                              Text(custMobile.isNotEmpty ? custMobile : 'No phone number',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (custAddress.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(custAddress, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                    if (custNotes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.notes_outlined, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(custNotes, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                    const Divider(height: 20),
                    // Quick Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: const Icon(Icons.add, color: Colors.white, size: 18),
                            label: const Text('Naya Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => NewOrderScreen(
                                    preSelectedCustomer: customerObj,
                                    onOrderCreated: _loadCustomerDetails,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366).withOpacity(0.1),
                          ),
                          icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                          onPressed: () {
                            PhoneUtils.openWhatsApp(
                              phone: custMobile,
                              message: 'Assalam-o-Alaikum $custName ji, Haroon Tailor se sampark kar rahe hain.',
                            );
                          },
                        ),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                          ),
                          icon: const Icon(Icons.phone, color: Colors.blue),
                          onPressed: () async {
                            if (custMobile.isNotEmpty) {
                              final uri = Uri.parse('tel:$custMobile');
                              if (await canLaunchUrl(uri)) launchUrl(uri);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. STATS ROW
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Orders', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('${orders.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Due (Baqaya)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          currency.format(totalBalance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: totalBalance > 0 ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 3. ORDER HISTORY (Point 7)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Order History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                Text('${orders.length} orders', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),

            if (orders.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Abhi tak koi order record nahi hai.'),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length,
                itemBuilder: (context, idx) {
                  final o = orders[idx];
                  final billNo = o['order_number'] ?? 'Bill-#${o['id']}';
                  final dateStr = o['order_date'] ?? '';
                  final totalAmt = o['total_amount'] ?? 0;
                  final remaining = o['remaining_amount'] ?? 0;
                  final status = (o['status'] ?? 'NEW').toString();
                  final clothingType = o['clothing_type'] ?? 'Custom';

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
                        // Open Order Details (Point 8)
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailsScreen(
                              orderId: o['id'],
                              onOrderUpdated: _loadCustomerDetails,
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
                                Text(billNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                                _buildStatusBadge(status),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$clothingType • ${_formatDate(dateStr)}',
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total: ${currency.format(totalAmt)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (remaining > 0)
                                  Text('Due: ${currency.format(remaining)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))
                                else
                                  const Text('Paid (0 due)',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

            // 4. SAVED MEASUREMENTS (IF ANY)
            if (profiles.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Saved Measurement Profiles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              ...profiles.map((p) {
                final pName = p['name'] ?? '${p['template_type'] ?? 'Garment'} Profile';
                final pType = p['template_type'] ?? '';
                final vals = Map<String, dynamic>.from(p['values'] ?? {});

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$pName ($pType)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: vals.entries.where((e) => e.value.toString().trim().isNotEmpty).map((e) {
                            return Chip(
                              backgroundColor: const Color(0xFFEEF2F6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                              label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label = status.replaceAll('_', ' ');

    switch (status) {
      case 'DELIVERED':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'STITCHING_COMPLETE':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        break;
      case 'PARTIALLY_COMPLETE':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        break;
      default:
        bg = Colors.purple.shade100;
        fg = Colors.purple.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString().split('T')[0]);
      return DateFormat('dd MMM yyyy').format(d);
    } catch (_) {
      return dateStr.toString();
    }
  }
}
