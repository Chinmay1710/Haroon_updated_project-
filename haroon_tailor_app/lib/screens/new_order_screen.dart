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
  final Map<String, dynamic>? initialMeasurements;
  final String? initialClothingType;
  final Map<String, dynamic>? editOrder;
  final VoidCallback? onOrderCreated;
  final VoidCallback? onOrderUpdated;

  const NewOrderScreen({
    super.key,
    this.preSelectedCustomer,
    this.initialMeasurements,
    this.initialClothingType,
    this.editOrder,
    this.onOrderCreated,
    this.onOrderUpdated,
  });

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
  bool _isEditMode = false;

  // Saved profiles for current customer
  List<dynamic> _savedProfiles = [];

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

    _isEditMode = widget.editOrder != null;

    if (_isEditMode) {
      _initEditOrder(widget.editOrder!);
    } else {
      if (widget.initialClothingType != null) {
        _clothingType = widget.initialClothingType!;
      }
      if (widget.initialMeasurements != null) {
        _applyMeasurements(widget.initialMeasurements!);
      }
      if (widget.preSelectedCustomer != null) {
        _selectCustomer(widget.preSelectedCustomer!);
      }
    }
  }

  void _initEditOrder(Map<String, dynamic> o) {
    final custId = o['customer_id'] ?? 0;
    final custName = o['customer_name'] ?? '';
    final custMobile = o['customer_mobile'] ?? '';
    _customer = Customer(id: custId, name: custName, mobile: custMobile);

    if (o['delivery_date'] != null) {
      try {
        _deliveryDate = DateTime.parse(o['delivery_date'].toString().split('T')[0]);
      } catch (_) {}
    }

    _orderNotesCtrl.text = (o['special_instructions'] ?? o['notes'] ?? '').toString();
    _advanceCtrl.text = (o['advance_amount'] ?? 0).toString();
    _discountCtrl.text = (o['discount'] ?? 0).toString();

    final items = (o['items'] as List<dynamic>?) ?? [];
    if (items.isNotEmpty) {
      final firstItem = items[0];
      _clothingType = firstItem['clothing_type'] ?? 'Shirt';
      _qtyCtrl.text = (firstItem['quantity'] ?? 1).toString();
      _priceCtrl.text = (firstItem['price'] ?? 0).toString();
      _itemNotesCtrl.text = (firstItem['notes'] ?? '').toString();

      final meas = (firstItem['measurements'] as Map<String, dynamic>?) ?? {};
      _applyMeasurements(meas);
    } else {
      _priceCtrl.text = (o['total_amount'] ?? 0).toString();
    }

    if (custId > 0) {
      _loadCustomerProfiles(custId);
    }
  }

  void _applyMeasurements(Map<String, dynamic> vals) {
    vals.forEach((k, v) {
      final key = k.toString().trim();
      final valStr = (v ?? '').toString().trim();
      if (_measurementControllers.containsKey(key)) {
        _measurementControllers[key]!.text = valStr;
      }
    });
    setState(() {});
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
    _loadCustomerProfiles(cust.id);
  }

  Future<void> _loadCustomerProfiles(int customerId) async {
    try {
      final profiles = await ApiService.getMeasurementsForCustomer(customerId);
      setState(() => _savedProfiles = profiles);

      // If user hasn't typed any measurements yet and there's a saved profile, pre-fill latest
      bool hasAnyMeas = _measurementControllers.values.any((c) => c.text.trim().isNotEmpty);
      if (!hasAnyMeas && profiles.isNotEmpty) {
        final latest = profiles.last;
        final vals = (latest['values'] as Map<String, dynamic>?) ?? {};
        _applyMeasurements(vals);
      }
    } catch (_) {}
  }

  void _showSavedMeasurementsSheet() {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle grahak (customer) select karein!'), backgroundColor: Colors.orange),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (_savedProfiles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.straighten, size: 48, color: Colors.blueGrey),
                const SizedBox(height: 12),
                Text(
                  '${_customer!.name} ka koi purana naap (saved profile) nahi mila.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aap naya naap niche diye gaye 24 boxes me darj kar sakte hain. Order save hote hi naap automatic save ho jayega.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                  child: const Text('Theek Hai', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Purana Naap Chunein',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A)),
                      ),
                      Text(
                        'Customer: ${_customer!.name}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(height: 20),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedProfiles.length,
                  itemBuilder: (context, idx) {
                    final p = _savedProfiles[_savedProfiles.length - 1 - idx]; // newest first
                    final pName = p['name'] ?? '${p['template_type'] ?? 'Garment'} Profile';
                    final type = p['template_type'] ?? 'Custom';
                    final dateStr = (p['created_at'] ?? '').toString().split('T')[0];
                    final vals = (p['values'] as Map<String, dynamic>?) ?? {};
                    final filledCount = vals.values.where((v) => (v ?? '').toString().trim().isNotEmpty).length;

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.1),
                          child: const Icon(Icons.straighten, color: Color(0xFF0F172A), size: 20),
                        ),
                        title: Text(pName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text(
                          '$type • $filledCount boxes bhare hue • $dateStr',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _applyMeasurements(vals);
                            if (_garmentTypes.contains(type)) {
                              setState(() => _clothingType = type);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('"$pName" ka naap 24 boxes me load ho gaya!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Use Naap', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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

  double get _advance => double.tryParse(_advanceCtrl.text.trim()) ?? 0.0;
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
  double get _remainingBalance => (_totalAmount - _discount) - _advance;

  Future<void> _submitOrder() async {
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

      if (_isEditMode) {
        // UPDATE EXISTING ORDER
        await ApiService.updateOrder(
          orderId: widget.editOrder!['id'],
          deliveryDate: DateFormat('yyyy-MM-dd').format(_deliveryDate),
          notes: _orderNotesCtrl.text.trim(),
          items: [
            {
              'clothing_type': _clothingType,
              'quantity': qty,
              'price': price,
              'measurements': measurements,
              'notes': _itemNotesCtrl.text.trim(),
              'image_base64': _imageBase64List,
            }
          ],
        );

        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order #${widget.editOrder!['order_number'] ?? widget.editOrder!['id']} update ho gaya!'),
              backgroundColor: Colors.green,
            ),
          );
          widget.onOrderUpdated?.call();
          Navigator.pop(context);
        }
      } else {
        // CREATE NEW ORDER
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
          final billNo = res['order_number'] ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order $billNo safaltapoorvak save ho gaya!'),
              backgroundColor: Colors.green,
            ),
          );

          // WhatsApp notification
          if (res['whatsapp_url'] != null) {
            await PhoneUtils.openBackendWhatsAppUrl(res['whatsapp_url'].toString());
          } else if (_sendWhatsapp) {
            // Exact Hindi website message format
            final shopSettings = await ApiService.getShopSettings();
            final shopName = shopSettings['shop_name'] ?? 'Haroon Tailor';
            final totalAmt = _totalAmount - _discount;
            final remainingAmt = _remainingBalance;
            final delivDateStr = DateFormat('dd/MM/yyyy').format(_deliveryDate);

            final msg =
                '$shopName ko chunne ke liye shukriya! Aapka order #$billNo safaltapoorvak darj kar liya gaya hai.\n\n'
                '👔 Kul Bill: Rs. $totalAmt\n'
                '💵 Jama Rashi: Rs. $_advance\n'
                '⏳ Baqaya Rashi: Rs. $remainingAmt\n'
                '📅 Delivery ki Tareekh: $delivDateStr\n\n'
                'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
                'Shukriya!\n$shopName';

            await PhoneUtils.openWhatsApp(_customer!.mobile, msg);
          }

          widget.onOrderCreated?.call();
          if (mounted) {
            Navigator.pop(context);
          }
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
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);
    final titleText = _isEditMode
        ? 'Edit Order #${widget.editOrder!['order_number'] ?? widget.editOrder!['id']}'
        : 'Naya Order Banayein';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. CUSTOMER SELECTION CARD
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Grahak (Customer) Details',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                        ),
                        if (!_isEditMode)
                          TextButton.icon(
                            icon: const Icon(Icons.person_search, size: 18),
                            label: Text(_customer == null ? 'Select Customer' : 'Change'),
                            onPressed: () async {
                              final selected = await Navigator.push<Customer>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CustomersScreen(isSelectMode: true),
                                ),
                              );
                              if (selected != null) {
                                _selectCustomer(selected);
                              }
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_customer == null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blueGrey),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text('Kripya upar "Select Customer" button se customer chunein.'),
                            ),
                          ],
                        ),
                      )
                    else
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          child: Text(_customer!.name.isNotEmpty ? _customer!.name[0].toUpperCase() : 'C'),
                        ),
                        title: Text(_customer!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Text(_customer!.mobile, style: TextStyle(color: Colors.grey.shade700)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: const Text('Selected', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. GARMENT & PRICING
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
                    const Text('Kapde Ka Prakar Aur Rate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _clothingType,
                      decoration: InputDecoration(
                        labelText: 'Kapda (Clothing Type)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: _garmentTypes
                          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
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
                            decoration: InputDecoration(
                              labelText: 'Quantity (Nag)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _priceCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              prefixText: 'Rs. ',
                              labelText: 'Per Item Price',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _itemNotesCtrl,
                      decoration: InputDecoration(
                        labelText: 'Item Notes (Design/Pattern)',
                        hintText: 'Jaise: Double pocket, Chinese collar...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. PHOTO ATTACHMENT CARD
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kapde Ki Photos (Attached)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${_imageBytesList.length} photo(s)', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Photo action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt, color: Color(0xFF0F172A)),
                            label: const Text('Camera', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library, color: Color(0xFF0F172A)),
                            label: const Text('Gallery', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_imageBytesList.isNotEmpty) ...[
                      const SizedBox(height: 14),
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
                                  right: 6,
                                  child: InkWell(
                                    onTap: () => _removePhoto(idx),
                                    child: const CircleAvatar(
                                      radius: 11,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close, color: Colors.white, size: 14),
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
            const SizedBox(height: 16),

            // 4. EXACT 24 MEASUREMENT BOXES GRID WITH OLD MEASUREMENT SELECTOR
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Naap Ke 24 Boxes',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                        ),
                        // USE OLD MEASUREMENT BUTTON (Point 3)
                        ElevatedButton.icon(
                          onPressed: _showSavedMeasurementsSheet,
                          icon: const Icon(Icons.history, size: 16, color: Colors.white),
                          label: const Text('Purana Naap', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Website jaisa 6x4 table grid. Kisi bhi box par click karein aur fraction bar se 1/4, 1/2 add karein.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),

                    // Measurement Grid (24 boxes)
                    MeasurementGrid(
                      controllers: _measurementControllers,
                      isReadOnly: false,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 5. DELIVERY DATE & SPECIAL INSTRUCTIONS
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
                    const Text('Delivery & Instruction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month, color: Color(0xFF0F172A)),
                      title: const Text('Delivery Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(DateFormat('dd MMMM yyyy (EEEE)').format(_deliveryDate)),
                      trailing: TextButton(
                        child: const Text('Badlein'),
                        onPressed: () async {
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
                    const SizedBox(height: 8),
                    TextField(
                      controller: _orderNotesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Special Instruction / Cloth Notes',
                        hintText: 'Jaise: Kapda grahak ne diya hai, button golden lagana...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 6. PAYMENT BREAKDOWN (Only in New Order mode)
            if (!_isEditMode) ...[
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
                      const Text('Payment Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _advanceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixText: 'Rs. ',
                                labelText: 'Advance Jama',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _discountCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                prefixText: 'Rs. ',
                                labelText: 'Discount',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Totals view
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
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
                        title: const Text('Send WhatsApp Bill on Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Website jaisa bill message customer ke WhatsApp par bheja jayega.', style: TextStyle(fontSize: 12)),
                        value: _sendWhatsapp,
                        activeThumbColor: const Color(0xFF25D366),
                        onChanged: (val) => setState(() => _sendWhatsapp = val),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 7. SUBMIT BUTTON
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isEditMode ? Icons.check_circle : Icons.save, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            _isEditMode ? 'Update Order' : 'Order Save Karein',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
