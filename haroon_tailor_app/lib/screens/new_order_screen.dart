import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import '../widgets/measurement_grid.dart';
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

  // 24 Measurement Controllers: 'Box 1' to 'Box 24'
  final Map<String, TextEditingController> _measurementControllers = {};

  // Photo management
  final ImagePicker _picker = ImagePicker();
  final List<Uint8List> _imageBytesList = [];
  final List<String> _imageBase64List = [];

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
      _measurementControllers['Box $i'] = TextEditingController();
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
    for (var ctrl in _measurementControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _selectCustomer(Customer cust) async {
    setState(() => _customer = cust);

    // Auto-fetch historical measurements for this customer
    try {
      final profiles = await ApiService.getMeasurementsForCustomer(cust.id);
      if (profiles.isNotEmpty) {
        final latest = profiles.last;
        final vals = latest['values'] ?? {};
        vals.forEach((k, v) {
          if (_measurementControllers.containsKey(k)) {
            _measurementControllers[k]!.text = v.toString();
          }
        });
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final base64Str = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _imageBytesList.add(bytes);
          _imageBase64List.add(base64Str);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _imageBytesList.removeAt(index);
      _imageBase64List.removeAt(index);
    });
  }

  void _viewFullImage(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  double get _totalAmount {
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
    return qty * price;
  }

  double get _discount {
    return double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
  }

  double get _advance {
    return double.tryParse(_advanceCtrl.text.trim()) ?? 0.0;
  }

  double get _remainingBalance {
    final total = _totalAmount - _discount;
    final bal = total - _advance;
    return bal < 0 ? 0.0 : bal;
  }

  void _saveOrder() async {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle grahak (customer) select karein!'), backgroundColor: Colors.orange),
      );
      return;
    }

    final price = double.tryParse(_priceCtrl.text.trim());
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kripya sahi kapde ka rate (price) bharein!'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Gather non-empty measurements
      final Map<String, String> measurements = {};
      _measurementControllers.forEach((k, ctrl) {
        final txt = ctrl.text.trim();
        if (txt.isNotEmpty) {
          measurements[k] = txt;
        }
      });

      final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;

      final payload = {
        'customer_id': _customer!.id,
        'customer_name': _customer!.name,
        'customer_mobile': _customer!.mobile,
        'delivery_date': DateFormat('yyyy-MM-dd').format(_deliveryDate),
        'advance_amount': _advance,
        'discount': _discount,
        'special_instructions': _orderNotesCtrl.text.trim(),
        'send_whatsapp': _sendWhatsapp,
        'items': [
          {
            'clothing_type': _clothingType,
            'quantity': qty,
            'price': price,
            'measurements': measurements,
            'notes': _itemNotesCtrl.text.trim(),
            'save_profile': true,
            'image_base64': _imageBase64List,
          }
        ]
      };

      final res = await ApiService.createOrder(payload);

      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order ${res['order_number'] ?? ''} safaltapoorvak save ho gaya!'),
            backgroundColor: Colors.green,
          ),
        );

        // Open WhatsApp bill if returned
        if (res['whatsapp_url'] != null) {
          await PhoneUtils.openBackendWhatsAppUrl(res['whatsapp_url'].toString());
        }

        widget.onOrderCreated?.call();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order save nahi hua: $e'), backgroundColor: Colors.red),
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
            _buildSectionHeader(Icons.person, '1. Grahak (Customer) Details'),
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
                        label: const Text('Grahak Select / Search Karein',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                            radius: 24,
                            backgroundColor: const Color(0xFF0F172A).withOpacity(0.1),
                            child: const Icon(Icons.person, color: Color(0xFF0F172A), size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_customer!.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_customer!.mobile,
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0F172A)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
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
                            child: const Text('Change', style: TextStyle(color: Color(0xFF0F172A))),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 2. GARMENT & PRICING
            _buildSectionHeader(Icons.checkroom, '2. Kapda & Rate (Garment)'),
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
                        labelText: 'Clothing Type',
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
            const SizedBox(height: 18),

            // 3. PHOTO ATTACHMENT SECTION (Point 1)
            _buildSectionHeader(Icons.photo_camera, '3. Photo(s) Attach Karein'),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            label: const Text('Camera', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _pickImage(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0F172A)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.photo_library, color: Color(0xFF0F172A), size: 20),
                            label: const Text('Gallery', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                            onPressed: () => _pickImage(ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                    if (_imageBytesList.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Attached Photos (${_imageBytesList.length}):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 90,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _imageBytesList.length,
                          itemBuilder: (context, idx) {
                            return Stack(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 10, top: 4),
                                  child: InkWell(
                                    onTap: () => _viewFullImage(_imageBytesList[idx]),
                                    borderRadius: BorderRadius.circular(10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey.shade300),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Image.memory(
                                          _imageBytesList[idx],
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: 4,
                                  child: InkWell(
                                    onTap: () => _removePhoto(idx),
                                    child: const CircleAvatar(
                                      radius: 11,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 4. 24 MEASUREMENT BOXES (Point 2 - Website 6x4 Grid)
            _buildSectionHeader(Icons.straighten, '4. Naap (24 Measurement Boxes - 6x4)'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: MeasurementGrid(
                  controllers: _measurementControllers,
                  isReadOnly: false,
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 5. DESIGN & DELIVERY INSTRUCTIONS
            _buildSectionHeader(Icons.edit_note, '5. Instructions (Design & Delivery)'),
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
                        labelText: 'Special Design Notes (Item level)',
                        hintText: 'e.g. Slim fit, 1 pocket, Chinese collar, Matching button...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _orderNotesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Delivery Instructions / Extra Note',
                        hintText: 'e.g. Urgent deliver by evening, customer will pickup...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // 6. DELIVERY DATE
            _buildSectionHeader(Icons.local_shipping, '6. Delivery Date'),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: const Icon(Icons.event, color: Color(0xFF0F172A)),
                title: const Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(DateFormat('dd MMMM yyyy (EEEE)').format(_deliveryDate)),
                trailing: const Icon(Icons.edit_calendar, color: Color(0xFF0F172A)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _deliveryDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _deliveryDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 18),

            // 7. PAYMENT DETAILS
            _buildSectionHeader(Icons.payments, '7. Payment & Advance'),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _discountCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Discount (₹)',
                              prefixText: '₹ ',
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
                              prefixText: '₹ ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bill:', style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(currency.format(_totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          if (_discount > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Discount:', style: TextStyle(color: Colors.green)),
                                Text('- ${currency.format(_discount)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                            Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Advance Rakam:'),
                              Text(currency.format(_advance), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Baqaya (Balance Due):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red)),
                              Text(currency.format(_remainingBalance),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.red)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send WhatsApp Bill Receipt', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Grahak ko WhatsApp par seedha receipt bhejega'),
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              onPressed: _isSubmitting ? null : _saveOrder,
              child: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 24),
                        SizedBox(width: 8),
                        Text('SAVE ORDER & BILL',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                      ],
                    ),
            ),
            const SizedBox(height: 40),
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
