import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import 'customers_screen.dart';

class NewOrderScreen extends StatefulWidget {
  final Customer? preSelectedCustomer;
  final VoidCallback? onOrderCreated;

  const NewOrderScreen({super.key, this.preSelectedCustomer, this.onOrderCreated});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  Customer? _customer;
  String _clothingType = 'Shirt';
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _itemNotesCtrl = TextEditingController();
  final TextEditingController _orderNotesCtrl = TextEditingController();
  final TextEditingController _advanceCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController();

  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 7));
  bool _sendWhatsapp = true;
  bool _isSubmitting = false;

  // 24 Measurement Boxes Controllers
  final Map<int, TextEditingController> _boxControllers = {};

  final List<String> _garmentTypes = [
    'Shirt',
    'Pant',
    'Kurta',
    'Pajama',
    'Safari Suit',
    'Blazer / Coat',
    'Sherwani',
    'Custom Item'
  ];

  @override
  void initState() {
    super.initState();
    for (int i = 1; i <= 24; i++) {
      _boxControllers[i] = TextEditingController();
    }
    if (widget.preSelectedCustomer != null) {
      _selectCustomer(widget.preSelectedCustomer!);
    }
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _itemNotesCtrl.dispose();
    _orderNotesCtrl.dispose();
    _advanceCtrl.dispose();
    _discountCtrl.dispose();
    for (var c in _boxControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _selectCustomer(Customer cust) async {
    setState(() => _customer = cust);
    try {
      final profiles = await ApiService.getMeasurementsForCustomer(cust.id);
      if (profiles.isNotEmpty) {
        final latest = profiles.last;
        final Map<String, dynamic> vals = latest['values'] ?? {};
        setState(() {
          for (int i = 1; i <= 24; i++) {
            final key = 'Box $i';
            if (vals.containsKey(key)) {
              _boxControllers[i]?.text = vals[key]?.toString() ?? '';
            }
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Grahak ke purane naap (measurements) auto-fill ho gaye!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  double get _totalPrice {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final discount = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    return (qty * price) - discount;
  }

  double get _remainingBalance {
    final advance = double.tryParse(_advanceCtrl.text.trim()) ?? 0;
    final remaining = _totalPrice - advance;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _submitOrder() async {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kripya pehle grahak (customer) chunein!'), backgroundColor: Colors.red),
      );
      return;
    }

    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kripya valid rate / price daalein!'), backgroundColor: Colors.red),
      );
      return;
    }

    // Collect 24 measurement boxes
    final Map<String, String> measurements = {};
    for (int i = 1; i <= 24; i++) {
      final val = _boxControllers[i]?.text.trim() ?? '';
      if (val.isNotEmpty) {
        measurements['Box $i'] = val;
      }
    }

    final itemNotes = _itemNotesCtrl.text.trim();
    final orderNotes = _orderNotesCtrl.text.trim();
    final combinedNotes = [orderNotes, itemNotes].where((s) => s.isNotEmpty).join(' | ');

    final payload = {
      'customerId': _customer!.id,
      'items': [
        {
          'clothing_type': _clothingType,
          'quantity': int.tryParse(_qtyCtrl.text.trim()) ?? 1,
          'price': price,
          'measurements': measurements,
          'save_profile': true,
          'notes': itemNotes,
        }
      ],
      'deliveryDate': DateFormat('yyyy-MM-dd').format(_deliveryDate),
      'advance': double.tryParse(_advanceCtrl.text.trim()) ?? 0,
      'discount': double.tryParse(_discountCtrl.text.trim()) ?? 0,
      'notes': combinedNotes,
      'paymentMethod': 'Cash',
      'send_whatsapp': _sendWhatsapp,
    };

    setState(() => _isSubmitting = true);

    try {
      final res = await ApiService.createOrder(payload);
      setState(() => _isSubmitting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order ${res['order_number'] ?? ''} successfully ban gaya!'),
            backgroundColor: Colors.green,
          ),
        );

        // Open WhatsApp if URL returned
        if (res['whatsapp_url'] != null) {
          final urlStr = res['whatsapp_url'].toString();
          final uri = Uri.parse(urlStr.startsWith('whatsapp://')
              ? urlStr.replaceFirst('whatsapp://send?', 'https://wa.me/').replaceAll('&text=', '?text=')
              : urlStr);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }

        widget.onOrderCreated?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save order: $e'), backgroundColor: Colors.red),
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
        title: const Text('Naya Order (New Order)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. CUSTOMER SELECTION CARD
            _buildSectionHeader(Icons.person, 'Grahak (Customer)'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_customer == null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.person_search, color: Colors.white),
                        label: const Text('Grahak Select / Search Karein', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomersScreen(
                                onSelectCustomer: (cust) {
                                  Navigator.pop(context);
                                  _selectCustomer(cust);
                                },
                              ),
                            ),
                          );
                        },
                      )
                    else
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: const Color(0xFF0F172A).withOpacity(0.1),
                            child: const Icon(Icons.person, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_customer!.mobile, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CustomersScreen(
                                    onSelectCustomer: (cust) {
                                      Navigator.pop(context);
                                      _selectCustomer(cust);
                                    },
                                  ),
                                ),
                              );
                            },
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. GARMENT & PRICING
            _buildSectionHeader(Icons.checkroom, 'Kapda & Rate (Garment)'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _clothingType,
                      decoration: InputDecoration(
                        labelText: 'Garment Type',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _garmentTypes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _clothingType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Price (₹) *',
                              prefixText: '₹ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. 24 MEASUREMENT BOXES
            _buildSectionHeader(Icons.straighten, '24 Measurement Boxes (Naap)'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: 24,
                      itemBuilder: (context, index) {
                        final boxNum = index + 1;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Box $boxNum',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 2),
                            Expanded(
                              child: TextField(
                                controller: _boxControllers[boxNum],
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.zero,
                                  filled: true,
                                  fillColor: const Color(0xFFF1F5F9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 4. INSTRUCTIONS & NOTES
            _buildSectionHeader(Icons.edit_note, 'Instructions & Khaas Hidayat'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _itemNotesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Design / Item Instructions',
                        hintText: 'Jaise: Slim fit, collar stiffness, no pocket...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _orderNotesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Delivery / Order Notes',
                        hintText: 'Jaise: Urgent delivery, kapda grahak ka hai...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 5. DELIVERY & PAYMENT
            _buildSectionHeader(Icons.payment, 'Delivery Date & Payment'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delivery Date', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('dd MMMM yyyy').format(_deliveryDate)),
                      trailing: const Icon(Icons.calendar_month, color: Color(0xFF0F172A)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _deliveryDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _deliveryDate = picked);
                      },
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _discountCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Discount (₹)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _advanceCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Advance Paid (₹)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bill:', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(currency.format(_totalPrice), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Remaining Balance:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                              Text(currency.format(_remainingBalance), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send WhatsApp Bill', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Grahak ko WhatsApp par seedha message bhejega'),
                      value: _sendWhatsapp,
                      activeColor: const Color(0xFF25D366),
                      onChanged: (val) => setState(() => _sendWhatsapp = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // SUBMIT BUTTON
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle, color: Colors.white),
                label: Text(
                  _isSubmitting ? 'Saving Order...' : 'SAVE & CREATE ORDER',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSubmitting ? null : _submitOrder,
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF0F172A)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }
}
