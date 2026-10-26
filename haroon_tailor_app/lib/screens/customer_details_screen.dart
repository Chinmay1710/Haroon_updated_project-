import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
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

  Future<void> _loadCustomerDetails({bool showLoading = true}) async {
    // 1. Instant local offline calculation (guarantees latest order status, payments, and remaining due from cached orders)
    final localData = await LocalStorageService.computeCustomerDetailsOffline(widget.customerId);
    if (localData.isNotEmpty && mounted) {
      setState(() {
        _customerData = localData;
        _isLoading = false;
        _errorMessage = null;
      });
    } else if (showLoading && _customerData == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    // 2. Fetch fresh updates from server in background if online
    if (!await LocalStorageService.isOfflineMode()) {
      try {
        final data = await ApiService.getCustomerDetails(widget.customerId);
        if (mounted && data.isNotEmpty) {
          final localOrders = (await LocalStorageService.computeCustomerDetailsOffline(widget.customerId))['orders'] ?? [];
          final mergedData = Map<String, dynamic>.from(data);
          if (localOrders is List && localOrders.isNotEmpty) {
            mergedData['orders'] = localOrders;
          }
          setState(() {
            _customerData = mergedData;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            if (_customerData == null) {
              _errorMessage = e.toString();
            }
          });
        }
      }
    }
  }

  // EDIT CUSTOMER MODAL (Point 4)
  void _showEditCustomerModal(Map<String, dynamic> c) {
    final nameCtrl = TextEditingController(text: c['name'] ?? '');
    String rawMobile = (c['mobile'] ?? '').toString().replaceAll('+91', '').replaceAll(' ', '').trim();
    rawMobile = rawMobile.replaceAll(RegExp(r'\D'), '');
    final mobileCtrl = TextEditingController(text: rawMobile);
    final addressCtrl = TextEditingController(text: c['address'] ?? '');
    final notesCtrl = TextEditingController(text: c['notes'] ?? '');
    String? phoneError;
    String? phoneHelper = '10 ank ka mobile number dalein';
    bool isPhoneValid = rawMobile.length == 10 && ['6', '7', '8', '9'].contains(rawMobile[0]);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void validatePhone(String val) {
              final clean = val.replaceAll(RegExp(r'\D'), '');
              if (clean.isEmpty) {
                phoneError = null;
                phoneHelper = '10 ank ka mobile number dalein';
                isPhoneValid = false;
              } else if (!['6', '7', '8', '9'].contains(clean[0])) {
                phoneError = 'Mobile number 6, 7, 8 ya 9 se shuru hona chahiye';
                phoneHelper = null;
                isPhoneValid = false;
              } else if (clean.length < 10) {
                phoneError = null;
                phoneHelper = '${clean.length}/10 ank darj kiye (10 ank zaroori)';
                isPhoneValid = false;
              } else {
                phoneError = null;
                phoneHelper = 'Sahi mobile number ✓';
                isPhoneValid = true;
              }
              setModalState(() {});
            }

            final canSave = !isSaving && isPhoneValid && nameCtrl.text.trim().isNotEmpty && phoneError == null;

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Edit Customer Profile',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
                      ),
                      IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const Divider(height: 20),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                    ],
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Customer Name *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: mobileCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onChanged: validatePhone,
                    decoration: InputDecoration(
                      prefixText: '+91 ',
                      prefixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 16),
                      labelText: 'Mobile Number *',
                      errorText: phoneError,
                      errorMaxLines: 2,
                      helperText: phoneError == null ? phoneHelper : null,
                      helperStyle: TextStyle(
                        color: isPhoneValid ? Colors.green.shade700 : Colors.grey.shade600,
                        fontWeight: isPhoneValid ? FontWeight.bold : FontWeight.normal,
                      ),
                      suffixIcon: isPhoneValid
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (phoneError != null
                              ? const Icon(Icons.error_outline, color: Colors.red)
                              : Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                                  child: Text(
                                    '${mobileCtrl.text.replaceAll(RegExp(r"\D"), "").length}/10',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                  ),
                                )),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressCtrl,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSave ? const Color(0xFF0F172A) : Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: !canSave
                          ? null
                          : () async {
                              final name = nameCtrl.text.trim();
                              final cleanMobile = mobileCtrl.text.replaceAll(RegExp(r'\D'), '');
                              if (name.isEmpty || cleanMobile.length != 10) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Kripya naam aur 10-digit mobile number bharein.'), backgroundColor: Colors.orange),
                                );
                                return;
                              }

                              setModalState(() => isSaving = true);
                              try {
                                await ApiService.updateCustomer(
                                  id: widget.customerId,
                                  name: name,
                                  mobile: '+91 $cleanMobile',
                                  address: addressCtrl.text.trim(),
                                  notes: notesCtrl.text.trim(),
                                );
                                if (ctx.mounted) {
                                  Navigator.pop(ctx);
                                }
                                _loadCustomerDetails();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Customer details updated!'), backgroundColor: Colors.green),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Update fail: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                      child: isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // USE PROFILE IN NEW ORDER (Point 3)
  void _useProfileInNewOrder(Customer cust, Map<String, dynamic> profile) {
    final type = profile['template_type'] ?? 'Shirt';
    final vals = (profile['values'] as Map<String, dynamic>?) ?? {};

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(
          preSelectedCustomer: cust,
          initialMeasurements: vals,
          initialClothingType: type,
          onOrderCreated: _loadCustomerDetails,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

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
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Edit Customer',
            onPressed: () => _showEditCustomerModal(c),
          ),
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
                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.1),
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
                              if (custMobile.isNotEmpty)
                                Text(custMobile, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                              if (custAddress.isNotEmpty)
                                Text(custAddress, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF0F172A)),
                          tooltip: 'Edit Customer Details',
                          onPressed: () => _showEditCustomerModal(c),
                        ),
                      ],
                    ),
                    if (custNotes.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.note_alt_outlined, color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(custNotes, style: TextStyle(color: Colors.amber.shade900, fontSize: 13)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(height: 24),
                    // Contact action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.call, size: 16),
                            label: const Text('Call'),
                            onPressed: () => PhoneUtils.callCustomer(custMobile),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                            ),
                            icon: const Icon(Icons.chat, size: 16, color: Colors.white),
                            label: const Text('WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => PhoneUtils.openWhatsApp(custMobile),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                          ),
                          icon: const Icon(Icons.add, size: 16, color: Colors.white),
                          label: const Text('New Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

            // 3. SAVED MEASUREMENT PROFILES (Point 3 - Use Old Measurements)
            if (profiles.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saved Naap (Profiles)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  Text('${profiles.length} profile(s)', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('$pName ($pType)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                            ElevatedButton.icon(
                              onPressed: () => _useProfileInNewOrder(customerObj, p),
                              icon: const Icon(Icons.add, size: 14, color: Colors.white),
                              label: const Text('Use in New Order', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                          ],
                        ),
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
              const SizedBox(height: 16),
            ],

            // 4. ORDER HISTORY
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
                      onTap: () async {
                        final orderIdNum = int.tryParse((o['id'] ?? '').toString()) ??
                            int.tryParse(RegExp(r'\d+').allMatches((o['order_number'] ?? '').toString()).lastOrNull?.group(0) ?? '') ??
                            0;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetailsScreen(
                              orderId: orderIdNum > 0 ? orderIdNum : (o['id'] is int ? o['id'] : 0),
                              onOrderUpdated: _loadCustomerDetails,
                            ),
                          ),
                        );
                        _loadCustomerDetails();
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
