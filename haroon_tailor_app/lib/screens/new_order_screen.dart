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

/// Single garment item draft inside a multi-garment order
class OrderItemDraft {
  String clothingType;
  int quantity;
  double price;
  Map<String, String> measurements;
  String notes;
  List<Uint8List> imageBytesList;
  List<String> imageBase64List;
  String existingImagePath;

  OrderItemDraft({
    this.clothingType = 'Shirt',
    this.quantity = 1,
    this.price = 0.0,
    Map<String, String>? measurements,
    this.notes = '',
    List<Uint8List>? imageBytesList,
    List<String>? imageBase64List,
    this.existingImagePath = '',
  })  : measurements = measurements ?? {},
        imageBytesList = imageBytesList ?? [],
        imageBase64List = imageBase64List ?? [];

  double get total => quantity * price;

  OrderItemDraft copy() {
    return OrderItemDraft(
      clothingType: clothingType,
      quantity: quantity,
      price: price,
      measurements: Map<String, String>.from(measurements),
      notes: notes,
      imageBytesList: List<Uint8List>.from(imageBytesList),
      imageBase64List: List<String>.from(imageBase64List),
      existingImagePath: existingImagePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'clothing_type': clothingType,
    'quantity': quantity,
    'price': price,
    'measurements': measurements,
    'notes': notes,
    'save_profile': true,
    'image_base64': imageBase64List,
  };
}

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
  final List<OrderItemDraft> _items = [];

  final TextEditingController _orderNotesCtrl = TextEditingController();
  final TextEditingController _advanceCtrl = TextEditingController();
  final TextEditingController _discountCtrl = TextEditingController();

  DateTime _deliveryDate = DateTime.now().add(const Duration(days: 7));
  bool _sendWhatsapp = true;
  bool _isSubmitting = false;
  bool _isEditMode = false;

  // Saved profiles for current customer
  List<dynamic> _savedProfiles = [];

  final ImagePicker _picker = ImagePicker();

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
    _isEditMode = widget.editOrder != null;

    if (_isEditMode) {
      _initEditOrder(widget.editOrder!);
    } else {
      if (widget.initialMeasurements != null || widget.initialClothingType != null) {
        final Map<String, String> m = {};
        widget.initialMeasurements?.forEach((k, v) {
          if (v != null && v.toString().trim().isNotEmpty) {
            m[k.toString().trim()] = v.toString().trim();
          }
        });
        _items.add(OrderItemDraft(
          clothingType: widget.initialClothingType ?? 'Shirt',
          quantity: 1,
          price: 0.0,
          measurements: m,
        ));
      }

      if (widget.preSelectedCustomer != null) {
        _selectCustomer(widget.preSelectedCustomer!);
      }
    }
  }

  Future<void> _initEditOrder(Map<String, dynamic> o) async {
    final orderId = o['id'] as int?;
    if (orderId != null && o['items'] is! List) {
      try {
        final fullOrder = await ApiService.getOrderDetails(orderId);
        o = fullOrder;
      } catch (_) {}
    }

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

    final dynamic itemsRaw = o['items'];
    _items.clear();
    if (itemsRaw is List && itemsRaw.isNotEmpty) {
      for (var it in itemsRaw) {
        if (it is Map) {
          final Map<String, String> m = {};
          final rawMeas = it['measurements'];
          if (rawMeas is Map) {
            rawMeas.forEach((k, v) {
              if (v != null && v.toString().trim().isNotEmpty) {
                m[k.toString().trim()] = v.toString().trim();
              }
            });
          }

          final List<String> b64 = [];
          if (it['image_base64'] is List) {
            b64.addAll((it['image_base64'] as List).map((e) => e.toString()));
          }

          _items.add(OrderItemDraft(
            clothingType: (it['clothing_type'] ?? 'Shirt').toString(),
            quantity: int.tryParse(it['quantity']?.toString() ?? '1') ?? 1,
            price: double.tryParse(it['price']?.toString() ?? '0') ?? 0.0,
            measurements: m,
            notes: (it['notes'] ?? '').toString(),
            imageBase64List: b64,
            existingImagePath: (it['image_path'] ?? '').toString(),
          ));
        }
      }
    }

    if (custId > 0) {
      _loadCustomerProfiles(custId);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _orderNotesCtrl.dispose();
    _advanceCtrl.dispose();
    _discountCtrl.dispose();
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
    } catch (_) {}
  }

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.total);
  double get _discount => double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
  double get _totalAmount => (_subtotal - _discount).clamp(0.0, double.infinity);
  double get _advance => double.tryParse(_advanceCtrl.text.trim()) ?? 0.0;
  double get _remainingBalance => (_totalAmount - _advance);

  // ─── ADD / EDIT GARMENT MODAL (Full 24-box Measurement Grid + Details) ─────
  Future<void> _openGarmentEditor({OrderItemDraft? existingItem, int? index}) async {
    final bool isEditing = existingItem != null;
    String tempType = existingItem?.clothingType ?? 'Shirt';
    final qtyCtrl = TextEditingController(text: (existingItem?.quantity ?? 1).toString());
    final priceCtrl = TextEditingController(
      text: existingItem != null && existingItem.price > 0 ? existingItem.price.toStringAsFixed(0) : '',
    );
    final notesCtrl = TextEditingController(text: existingItem?.notes ?? '');

    // 24 measurement box controllers
    final Map<String, TextEditingController> tempControllers = {};
    for (int i = 1; i <= 24; i++) {
      final key = 'Box $i';
      tempControllers[key] = TextEditingController(
        text: existingItem?.measurements[key] ?? '',
      );
    }

    final List<Uint8List> tempBytes = List<Uint8List>.from(existingItem?.imageBytesList ?? []);
    final List<String> tempB64 = List<String>.from(existingItem?.imageBase64List ?? []);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setEditorState) {
            final qtyVal = int.tryParse(qtyCtrl.text.trim()) ?? 1;
            final priceVal = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
            final itemTotal = qtyVal * priceVal;

            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Top Drag Handle & Title Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F172A),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.checkroom, color: Colors.white, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              isEditing ? 'Kapda Sudharein (Edit Garment)' : 'Naya Kapda Jodein (+ Add Garment)',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Form Content Scrollable
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Clothing Type & Pricing Row
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Kapde Ka Prakar (Garment Type)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: tempType,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.style, color: Color(0xFF0F172A)),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                    items: _garmentTypes.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setEditorState(() => tempType = val);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: TextFormField(
                                          controller: qtyCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: 'Quantity (Sankhya)',
                                            prefixIcon: const Icon(Icons.tag, size: 20),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onChanged: (_) => setEditorState(() {}),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: TextFormField(
                                          controller: priceCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(
                                            labelText: 'Rate / Price (Rs.)',
                                            prefixText: 'Rs. ',
                                            prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onChanged: (_) => setEditorState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('$tempType Subtotal:', style: const TextStyle(fontWeight: FontWeight.w600)),
                                        Text('Rs. ${itemTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 2. Measurement Grid Card (with Old Measurement button)
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('24 Measurement Boxes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          Text('$tempType ke naap darj karein', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                        ],
                                      ),
                                      if (_customer != null && _savedProfiles.isNotEmpty)
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.history_edu, size: 16, color: Colors.white),
                                          label: const Text('Purana Naap', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF2563EB),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: () {
                                            _showOldMeasurementsPicker(
                                              onSelect: (vals) {
                                                setEditorState(() {
                                                  vals.forEach((k, v) {
                                                    final key = k.toString().trim();
                                                    final val = (v ?? '').toString().trim();
                                                    if (tempControllers.containsKey(key)) {
                                                      tempControllers[key]!.text = val;
                                                    }
                                                  });
                                                });
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Purana naap $tempType me copy ho gaya!'), backgroundColor: Colors.green),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  MeasurementGrid(controllers: tempControllers),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 3. Photo Attachment Card
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('Kapde Ki Photo (Attachments)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      Row(
                                        children: [
                                          IconButton.filledTonal(
                                            icon: const Icon(Icons.camera_alt, size: 18),
                                            onPressed: () async {
                                              final picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
                                              if (picked != null) {
                                                final bytes = await picked.readAsBytes();
                                                final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                                                setEditorState(() {
                                                  tempBytes.add(bytes);
                                                  tempB64.add(b64);
                                                });
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton.filledTonal(
                                            icon: const Icon(Icons.photo_library, size: 18),
                                            onPressed: () async {
                                              final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, maxHeight: 1920, imageQuality: 85);
                                              if (picked != null) {
                                                final bytes = await picked.readAsBytes();
                                                final b64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                                                setEditorState(() {
                                                  tempBytes.add(bytes);
                                                  tempB64.add(b64);
                                                });
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  if (tempBytes.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 80,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: tempBytes.length,
                                        itemBuilder: (ctx, idx) {
                                          return Stack(
                                            children: [
                                              Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                width: 80,
                                                height: 80,
                                                decoration: BoxDecoration(
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: Colors.grey.shade300),
                                                  image: DecorationImage(image: MemoryImage(tempBytes[idx]), fit: BoxFit.cover),
                                                ),
                                              ),
                                              Positioned(
                                                top: 2,
                                                right: 10,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setEditorState(() {
                                                      tempBytes.removeAt(idx);
                                                      tempB64.removeAt(idx);
                                                    });
                                                  },
                                                  child: const CircleAvatar(
                                                    radius: 10,
                                                    backgroundColor: Colors.red,
                                                    child: Icon(Icons.close, size: 12, color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ] else
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text('Sample kapda ya design ki photo jodne ke liye camera/gallery button dabayein.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4. Notes for this Garment
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Is Kapde Ki Vishesh Tippani (Notes)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: notesCtrl,
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      hintText: 'Jaise: Collar Chinese rahega, single pocket, etc.',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Save Garment Button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
                      ],
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          isEditing ? 'Kapda Update Karein (Rs. ${itemTotal.toStringAsFixed(0)})' : 'Is Kapde Ko Order Me Jodein (Rs. ${itemTotal.toStringAsFixed(0)})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          final parsedPrice = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                          final parsedQty = int.tryParse(qtyCtrl.text.trim()) ?? 1;

                          if (parsedPrice <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Kripya is kapde ka rate (price) bharein!'), backgroundColor: Colors.orange),
                            );
                            return;
                          }

                          // Gather 24 measurements
                          final Map<String, String> m = {};
                          tempControllers.forEach((k, ctrl) {
                            final txt = ctrl.text.trim();
                            if (txt.isNotEmpty) {
                              m[k] = txt;
                            }
                          });

                          final draft = OrderItemDraft(
                            clothingType: tempType,
                            quantity: parsedQty,
                            price: parsedPrice,
                            measurements: m,
                            notes: notesCtrl.text.trim(),
                            imageBytesList: tempBytes,
                            imageBase64List: tempB64,
                            existingImagePath: existingItem?.existingImagePath ?? '',
                          );

                          setState(() {
                            if (isEditing && index != null) {
                              _items[index] = draft;
                            } else {
                              _items.add(draft);
                            }
                          });

                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$tempType order me jud gaya!'),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
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

  // Duplicate Garment helper
  void _duplicateGarment(int index) {
    final original = _items[index];
    setState(() {
      _items.add(original.copy());
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${original.clothingType} duplicate ho gaya!'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Delete Garment helper
  void _deleteGarment(int index) {
    final removedName = _items[index].clothingType;
    setState(() {
      _items.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$removedName order se hata diya gaya'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Helper for picking saved profile inside garment editor
  void _showOldMeasurementsPicker({required Function(Map<String, dynamic>) onSelect}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        if (_savedProfiles.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Koi purana naap nahi mila.', textAlign: TextAlign.center),
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
                  const Text('Purana Naap Chunein', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(height: 20),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _savedProfiles.length,
                  itemBuilder: (context, idx) {
                    final p = _savedProfiles[_savedProfiles.length - 1 - idx];
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
                        subtitle: Text('$type • $filledCount boxes • $dateStr', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        trailing: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            onSelect(vals);
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

  void _viewFullImage(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SUBMIT ORDER ──────────────────────────────────────────────────────────
  Future<void> _submitOrder() async {
    if (_customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pehle grahak (customer) select karein!'), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kripya kam se kam ek kapda jodein!'), backgroundColor: Colors.orange),
      );
      _openGarmentEditor();
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final itemsPayload = _items.map((i) => i.toJson()).toList();

      if (_isEditMode) {
        // UPDATE EXISTING ORDER
        await ApiService.updateOrder(
          orderId: widget.editOrder!['id'],
          deliveryDate: DateFormat('yyyy-MM-dd').format(_deliveryDate),
          notes: _orderNotesCtrl.text.trim(),
          items: itemsPayload,
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
          'customerId': _customer!.id,
          'customer_id': _customer!.id,
          'customer_name': _customer!.name,
          'customer_mobile': _customer!.mobile,
          'deliveryDate': DateFormat('yyyy-MM-dd').format(_deliveryDate),
          'delivery_date': DateFormat('yyyy-MM-dd').format(_deliveryDate),
          'advance': _advance,
          'advance_amount': _advance,
          'discount': _discount,
          'notes': _orderNotesCtrl.text.trim(),
          'special_instructions': _orderNotesCtrl.text.trim(),
          'send_whatsapp': _sendWhatsapp,
          'items': itemsPayload,
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
            final shopSettings = await ApiService.getShopSettings();
            final shopName = shopSettings['shop_name'] ?? 'Haroon Tailor';
            final totalAmt = _totalAmount;
            final remainingAmt = _remainingBalance;
            final delivDateStr = DateFormat('dd/MM/yyyy').format(_deliveryDate);
            final itemsStr = _items.map((i) => '${i.quantity} ${i.clothingType}').join(', ');

            final msg =
                '✨ ${_customer!.name}! ✨\n\n'
                '$shopName ko chunne ke liye shukriya! Aapka order #$billNo ($itemsStr) safaltapoorvak darj kar liya gaya hai.\n\n'
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
            // ─── 1. CUSTOMER SELECTION CARD ────────────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade300),
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

            // ─── 2. MULTIPLE GARMENTS / KAPDE SECTION ──────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.checkroom, color: Color(0xFF0F172A), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Kapde / Garments (${_items.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16, color: Colors.white),
                          label: const Text('Kapda Jodein', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openGarmentEditor(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Empty State or List of Garments
                    if (_items.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.checkroom, size: 48, color: Colors.grey),
                            const SizedBox(height: 10),
                            const Text(
                              'Is order me abhi tak koi kapda add nahi hua.',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kurta, Pant, Shirt ya koi bhi kapda aur uska 24-box naap jodne ke liye niche button dabayein.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('+ Pehla Kapda Jodein', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _openGarmentEditor(),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      // List of added garment cards
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, idx) {
                          final item = _items[idx];
                          final filledBoxes = item.measurements.entries.where((e) => e.value.trim().isNotEmpty).toList();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Garment Name & Price
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.1),
                                          child: const Icon(Icons.style, size: 18, color: Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.clothingType,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            Text(
                                              'Qty: ${item.quantity} × Rs. ${item.price.toStringAsFixed(0)}',
                                              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Rs. ${item.total.toStringAsFixed(0)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                      ),
                                    ),
                                  ],
                                ),

                                // Measurement Chips Preview
                                if (filledBoxes.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: filledBoxes.take(8).map((e) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.grey.shade300),
                                        ),
                                        child: Text(
                                          '${e.key}: ${e.value}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                        ),
                                      );
                                    }).toList()
                                      ..addAll(filledBoxes.length > 8
                                          ? [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                child: Text('+${filledBoxes.length - 8} more', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                              )
                                            ]
                                          : []),
                                  ),
                                ],

                                // Photo Thumbnails Preview
                                if (item.imageBytesList.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 44,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: item.imageBytesList.length,
                                      itemBuilder: (ctx, pIdx) {
                                        return GestureDetector(
                                          onTap: () => _viewFullImage(item.imageBytesList[pIdx]),
                                          child: Container(
                                            margin: const EdgeInsets.only(right: 6),
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.grey.shade300),
                                              image: DecorationImage(image: MemoryImage(item.imageBytesList[pIdx]), fit: BoxFit.cover),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],

                                // Notes Preview
                                if (item.notes.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.edit_note, size: 16, color: Colors.blueGrey),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          item.notes,
                                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],

                                const Divider(height: 16),

                                // Action Buttons (Edit, Duplicate, Delete)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit, size: 16, color: Color(0xFF2563EB)),
                                      label: const Text('Edit', style: TextStyle(color: Color(0xFF2563EB), fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: () => _openGarmentEditor(existingItem: item, index: idx),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.content_copy, size: 16, color: Color(0xFF475569)),
                                      label: const Text('Duplicate', style: TextStyle(color: Color(0xFF475569), fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: () => _duplicateGarment(idx),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                      label: const Text('Delete', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                                      onPressed: () => _deleteGarment(idx),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add_circle_outline, color: Color(0xFF0F172A)),
                        label: const Text('+ Aur Kapda Jodein (+ Add Another Garment)', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF0F172A), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _openGarmentEditor(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── 3. BILL SUMMARY & ADVANCE PAYMENT ─────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bill & Bhugtan (Payment)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),

                    // Subtotal Display
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kul Kapdo Ka Total (Subtotal):', style: TextStyle(fontSize: 14)),
                        Text('Rs. ${_subtotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Discount & Advance inputs
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _discountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Chhoot (Discount)',
                              prefixText: 'Rs. ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _advanceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Advance (Jama Rashi)',
                              prefixText: 'Rs. ',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Total & Remaining Box
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Final Total Bill:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text('Rs. ${_totalAmount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                            ],
                          ),
                          const Divider(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Baqaya (Remaining Balance):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text(
                                'Rs. ${_remainingBalance.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: _remainingBalance > 0 ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── 4. DELIVERY DATE & GENERAL NOTES ─────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Delivery Ki Tareekh Aur Order Notes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFF0F172A),
                        child: Icon(Icons.calendar_today, color: Colors.white, size: 20),
                      ),
                      title: const Text('Delivery Date', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      subtitle: Text(
                        DateFormat('dd MMMM yyyy (EEEE)').format(_deliveryDate),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _deliveryDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _deliveryDate = picked);
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                        child: const Text('Badlein', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _orderNotesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Order Ke Liye Special Notes / Hidayat (Optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('WhatsApp Confirmation Bhejein', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Order bante hi grahak ko WhatsApp bill message jayega'),
                      value: _sendWhatsapp,
                      activeColor: Colors.green,
                      onChanged: (val) => setState(() => _sendWhatsapp = val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ─── 5. SUBMIT ORDER BUTTON ────────────────────────────────────
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('Order Save Ho Raha Hai...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    )
                  : Text(
                      _isEditMode ? 'Order Update Karein' : 'Order Darj Karein (${_items.length} Kapde • Rs. ${_totalAmount.toStringAsFixed(0)})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
