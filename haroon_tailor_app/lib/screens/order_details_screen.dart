import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/customer.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
import '../utils/phone_utils.dart';
import '../widgets/measurement_grid.dart';
import '../utils/io_helper_stub.dart'
    if (dart.library.html) '../utils/io_helper_web.dart'
    if (dart.library.io) '../utils/io_helper_io.dart';
import 'new_order_screen.dart';
import 'receipt_print_screen.dart';
import 'stitching_slip_print_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final int orderId;
  final VoidCallback? onOrderUpdated;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    this.onOrderUpdated,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _order;
  final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder({bool showLoading = true}) async {
    // 1. Instant local cache load (0 milliseconds delay!)
    final cached = await LocalStorageService.getCachedOrderDetails(widget.orderId);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _order = cached;
        _isLoading = false;
      });
    } else if (showLoading && _order == null) {
      setState(() => _isLoading = true);
    }

    // 2. Fetch fresh updates from server in background
    try {
      final data = await ApiService.getOrderDetails(widget.orderId);
      if (mounted) {
        setState(() {
          _order = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        if (_order == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order load nahi hua: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 1. COMPLETE BUTTON WITH WHATSAPP CONFIRMATION (Point 2)
  void _handleComplete() async {
    if (_order == null) return;
    final billNo = _order!['order_number'] ?? '#${widget.orderId}';
    bool sendWhatsapp = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: const Text('Mark Stitching Complete?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order $billNo ko Stitching Complete mark karein? Iska matlab kapde delivery ke liye tayyar hain.'),
                  const SizedBox(height: 14),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Send WhatsApp Notification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Website jaisa "Kapde tayyar hain" message customer ke WhatsApp par bheja jayega.', style: TextStyle(fontSize: 12)),
                    value: sendWhatsapp,
                    activeColor: const Color(0xFF25D366),
                    onChanged: (val) => setDlgState(() => sendWhatsapp = val ?? true),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true) {
      try {
        final res = await ApiService.updateOrderStatus(
          orderId: widget.orderId,
          status: 'STITCHING_COMPLETE',
          sendWhatsapp: sendWhatsapp,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order marked as Stitching Complete'), backgroundColor: Colors.green),
          );
        }

        // WhatsApp notification (exact website message)
        if (sendWhatsapp) {
          if (res['whatsapp_url'] != null) {
            await PhoneUtils.openBackendWhatsAppUrl(res['whatsapp_url'].toString());
          } else {
            final phone = (_order!['customer_mobile'] ?? '').toString();
            final custName = _order!['customer_name'] ?? 'Grahak';
            final shopSettings = await ApiService.getShopSettings();
            final shopName = shopSettings['shop_name'] ?? 'Haroon Tailor';
            final dynamic itemsRaw = _order!['items'];
            final String itemsStr = itemsRaw is String
                ? (itemsRaw.isNotEmpty ? itemsRaw : 'Kapde')
                : (itemsRaw is List && itemsRaw.isNotEmpty
                    ? itemsRaw.map((i) => '${i['quantity'] ?? 1} ${i['clothing_type'] ?? 'Kapde'}').join(', ')
                    : 'Kapde');

            final msg =
                '🎉 $custName! 🎉\n\n'
                'Aapka order #$billNo ($itemsStr) ab bilkul tayyar hai! Aap ise $shopName se le ja sakte hain.\n\n'
                'Kripya apni suvidha anusar dukan par aayein aur apne sile hue kapde prapt karein.\n\n'
                'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
                'Jald milenge!\n$shopName';

            await PhoneUtils.openWhatsApp(phone, msg);
          }
        }

        widget.onOrderUpdated?.call();
        _loadOrder();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 2. PARTIAL BUTTON WITH CHECKBOXES MODAL (Point 1 - Website Flow)
  void _handlePartial() {
    if (_order == null) return;
    final dynamic rawItemsVal = _order!['raw_items'];
    final dynamic itemsVal = _order!['items'];

    // Extract item list with id, name, is_ready
    final List<Map<String, dynamic>> itemList = [];

    if (rawItemsVal is List && rawItemsVal.isNotEmpty) {
      for (var it in rawItemsVal) {
        if (it is Map) {
          itemList.add({
            'id': it['id'] ?? 0,
            'name': (it['name'] ?? 'Item').toString(),
            'is_ready': it['is_ready'] == true,
          });
        }
      }
    } else if (itemsVal is List && itemsVal.isNotEmpty) {
      for (var it in itemsVal) {
        if (it is Map) {
          itemList.add({
            'id': it['id'] ?? 0,
            'name': '${it['clothing_type'] ?? 'Custom Item'} (x${it['quantity'] ?? 1})',
            'is_ready': it['is_ready'] == true,
          });
        }
      }
    }

    if (itemList.isEmpty) {
      // Fallback if no items array
      _updateStatusSimple('PARTIALLY_COMPLETE');
      return;
    }

    // Modal with checkboxes matching website's openPartialModal
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final allChecked = itemList.every((i) => i['is_ready'] == true);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: const [
                  Icon(Icons.checklist, color: Color(0xFFD97706)),
                  SizedBox(width: 8),
                  Text('Partially Complete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Jo kapde sil kar tayyar hain unhe tick karein:',
                      style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: itemList.length,
                        itemBuilder: (context, idx) {
                          final item = itemList[idx];
                          final isChecked = item['is_ready'] == true;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isChecked ? Colors.amber.shade50 : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isChecked ? Colors.amber.shade400 : Colors.grey.shade300,
                              ),
                            ),
                            child: CheckboxListTile(
                              title: Text(
                                item['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: isChecked ? const Color(0xFF0F172A) : Colors.grey.shade800,
                                ),
                              ),
                              value: isChecked,
                              activeColor: const Color(0xFFD97706),
                              onChanged: (val) {
                                setModalState(() {
                                  item['is_ready'] = val ?? false;
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final readyIds = itemList
                        .where((i) => i['is_ready'] == true)
                        .map((i) => int.tryParse(i['id'].toString()) ?? 0)
                        .where((id) => id > 0)
                        .toList();

                    try {
                      await ApiService.updateOrderStatus(
                        orderId: widget.orderId,
                        status: allChecked ? 'STITCHING_COMPLETE' : 'PARTIALLY_COMPLETE',
                        readyItemIds: readyIds,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Items updated successfully!'), backgroundColor: Colors.green),
                        );
                      }
                      widget.onOrderUpdated?.call();
                      _loadOrder();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Update error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  child: const Text('Save Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _updateStatusSimple(String newStatus) async {
    try {
      await ApiService.updateOrderStatus(
        orderId: widget.orderId,
        status: newStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to $newStatus'), backgroundColor: Colors.green),
        );
      }
      widget.onOrderUpdated?.call();
      _loadOrder();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 3. DELIVER BUTTON WITH PAYMENT PROMPT
  void _handleDeliver() async {
    if (_order == null) return;
    final remaining = double.tryParse((_order!['remaining_amount'] ?? 0).toString()) ?? 0.0;

    if (remaining > 0) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
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
                              const Text('Baqaya Rakam (Pending Payment)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text('Remaining Balance: ${currency.format(remaining)}',
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
                      decoration: InputDecoration(
                        prefixText: 'Rs. ',
                        labelText: 'Payment Amount',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: payMethod,
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
                            onPressed: () {
                              Navigator.pop(ctx);
                              _updateStatusSimple('DELIVERED');
                            },
                            child: const Text('Bina Payment Deliver', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
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
                                  orderId: widget.orderId,
                                  amount: amt,
                                  paymentMethod: payMethod,
                                  sendWhatsapp: true,
                                );
                              } catch (_) {}
                              _updateStatusSimple('DELIVERED');
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
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark Delivered?'),
          content: Text('Order ${_order!['order_number']} deliver mark karein?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Deliver', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        _updateStatusSimple('DELIVERED');
      }
    }
  }

  // 4. DELETE ORDER (Frees bill number for reuse)
  void _handleDelete() async {
    if (_order == null) return;
    final billNo = _order!['order_number'] ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Order $billNo?'),
        content: Text(
          'Kya aap sach me order $billNo delete karna chahte hain?\n\n'
          'Delete karne ke baad yeh bill number agle naye order ke liye dobara reuse hoga.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Karein', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService.deleteOrder(widget.orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Order $billNo delete ho gaya aur bill number reuse ho sakta hai.'), backgroundColor: Colors.red),
          );
          widget.onOrderUpdated?.call();
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete fail: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 5. EDIT ORDER (Point 4)
  void _handleEditOrder() {
    if (_order == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(
          editOrder: _order,
          onOrderUpdated: () {
            _loadOrder();
            widget.onOrderUpdated?.call();
          },
        ),
      ),
    );
  }

  // 6. USE MEASUREMENTS IN NEW ORDER (Point 3)
  void _useMeasurementsInNewOrder() {
    if (_order == null) return;
    final cust = Customer(
      id: _order!['customer_id'] ?? 0,
      name: _order!['customer_name'] ?? '',
      mobile: _order!['customer_mobile'] ?? '',
    );
    final dynamic itemsRaw = (_order!['items_detail'] is List && (_order!['items_detail'] as List).isNotEmpty)
        ? _order!['items_detail']
        : (_order!['raw_items'] is List && (_order!['raw_items'] as List).isNotEmpty
            ? _order!['raw_items']
            : (_order!['items'] is List ? _order!['items'] : []));
    final List<dynamic> items = itemsRaw is List ? itemsRaw : [];
    Map<String, dynamic> measurements = {};
    String clothingType = 'Shirt';

    if (items.isNotEmpty) {
      clothingType = items[0]['clothing_type'] ?? 'Shirt';
      measurements = (items[0]['measurements'] as Map<String, dynamic>?) ?? {};
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewOrderScreen(
          preSelectedCustomer: cust,
          initialMeasurements: measurements,
          initialClothingType: clothingType,
          onOrderCreated: widget.onOrderUpdated,
        ),
      ),
    );
  }

  // 7. PRINT CUSTOMER BILL (Point 5)
  void _openPrintReceipt() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptPrintScreen(
          orderId: widget.orderId,
          initialOrder: _order,
        ),
      ),
    );
  }

  // 8. PRINT STITCHING BILL (Point 5)
  void _openPrintStitchingSlip() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StitchingSlipPrintScreen(
          orderId: widget.orderId,
          initialOrder: _order,
        ),
      ),
    );
  }

  void _sendWhatsAppReceipt() async {
    if (_order == null) return;
    final phone = (_order!['customer_mobile'] ?? '').toString();
    final billNo = _order!['order_number'] ?? '';
    final custName = _order!['customer_name'] ?? 'Grahak';
    final total = _order!['total_amount'] ?? 0;
    final remaining = _order!['remaining_amount'] ?? 0;
    final advance = _order!['advance_amount'] ?? 0;
    final delivDate = _order!['delivery_date'] != null
        ? _order!['delivery_date'].toString().split('T')[0]
        : '-';

    final msg =
        'Assalam-o-Alaikum $custName ji,\n'
        'Haroon Tailor ko chunne ke liye shukriya!\n\n'
        'Aapka order #$billNo details:\n'
        '👔 Total Bill: Rs. $total\n'
        '💵 Jama Rakam: Rs. $advance\n'
        '⏳ Baqaya Rakam: Rs. $remaining\n'
        '📅 Delivery Date: $delivDate\n\n'
        'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
        'Shukriya!\nHaroon Tailor';

    await PhoneUtils.openWhatsApp(phone, msg);
  }

  void _viewFullImage(String url) {
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
              child: InteractiveViewer(
                clipBehavior: Clip.none,
                child: buildSmartImage(url, fit: BoxFit.contain),
              ),
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

  List<String> _extractItemPhotos(dynamic it) {
    if (it is! Map) return [];
    final List<String> raw = [];
    if (it['image_path'] != null) raw.addAll(LocalStorageService.sanitizePhotoList(it['image_path']));
    if (it['image_base64'] != null) raw.addAll(LocalStorageService.sanitizePhotoList(it['image_base64']));
    if (it['images'] != null) raw.addAll(LocalStorageService.sanitizePhotoList(it['images']));
    return LocalStorageService.sanitizePhotoList(raw);
  }

  List<String> _extractOrderPhotos(Map<String, dynamic> o) {
    final List<String> raw = [];
    if (o['cloth_photos'] != null) raw.addAll(LocalStorageService.sanitizePhotoList(o['cloth_photos']));
    if (o['image_path'] != null) raw.addAll(LocalStorageService.sanitizePhotoList(o['image_path']));
    return LocalStorageService.sanitizePhotoList(raw);
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'DELIVERED':
        return Colors.green;
      case 'STITCHING_COMPLETE':
        return Colors.blue;
      case 'PARTIALLY_COMPLETE':
        return Colors.orange;
      case 'CANCELLED':
        return Colors.red;
      default:
        return const Color(0xFF0F172A);
    }
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget? _buildDeliveryAlertBadge(Map<String, dynamic> o) {
    final status = (o['status'] ?? '').toString();
    if (status == 'DELIVERED' || status == 'CANCELLED' || status == 'STITCHING_COMPLETE') {
      return null;
    }

    final delivStr = o['delivery_date']?.toString();
    if (delivStr == null || delivStr.trim().isEmpty) {
      return null;
    }

    final dDate = DateTime.tryParse(delivStr.split('T')[0]);
    if (dDate == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(dDate.year, dDate.month, dDate.day);
    final diffDays = targetDate.difference(today).inDays;

    String label;
    Color bgColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    if (diffDays < 0) {
      final lateDays = -diffDays;
      label = lateDays == 1 ? 'OVERDUE (1 Din Late)' : 'OVERDUE ($lateDays Din Late)';
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFDC2626);
      borderColor = const Color(0xFFEF4444);
      icon = Icons.error_rounded;
    } else if (diffDays == 0) {
      label = 'DELIVERY AAJ HAI (Today)';
      bgColor = const Color(0xFFFEE2E2);
      textColor = const Color(0xFFE11D48);
      borderColor = const Color(0xFFF43F5E);
      icon = Icons.alarm;
    } else if (diffDays == 1) {
      label = 'DELIVERY KAL HAI (1 Din Bacha)';
      bgColor = const Color(0xFFFFF7ED);
      textColor = const Color(0xFFEA580C);
      borderColor = const Color(0xFFF97316);
      icon = Icons.warning_amber_rounded;
    } else if (diffDays <= 3) {
      label = '$diffDays Din Mein Delivery Baki';
      bgColor = const Color(0xFFFEFCE8);
      textColor = const Color(0xFFCA8A04);
      borderColor = const Color(0xFFEAB308);
      icon = Icons.hourglass_top_rounded;
    } else {
      return null;
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateColumn(String label, dynamic dateVal, {bool isDelivery = false}) {
    final str = dateVal != null ? dateVal.toString().split('T')[0] : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(
          str,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isDelivery ? Colors.blue.shade900 : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Details'), backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order Details'), backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
        body: const Center(child: Text('Order nahi mila')),
      );
    }

    final o = _order!;
    final billNo = o['order_number'] ?? '#${o['id']}';
    final custName = o['customer_name'] ?? 'Walk-in Customer';
    final phone = (o['customer_mobile'] ?? '').toString();
    final address = (o['customer_address'] ?? '').toString();
    final status = (o['status'] ?? 'NEW').toString();
    final dynamic itemsRaw = (o['items_detail'] is List && (o['items_detail'] as List).isNotEmpty)
        ? o['items_detail']
        : (o['items'] is List ? o['items'] : []);
    final List<dynamic> items = itemsRaw is List ? itemsRaw : [];
    final payments = (o['payments'] as List<dynamic>?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(billNo, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Order',
            onPressed: _handleEditOrder,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Delete Order',
            onPressed: _handleDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. BILL & STATUS SUMMARY CARD
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
                        Text(billNo, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                        _buildStatusBadge(status),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDateColumn('Order Date', o['order_date']),
                        _buildDateColumn('Delivery Date', o['delivery_date'], isDelivery: true),
                      ],
                    ),
                    if (_buildDeliveryAlertBadge(o) != null) ...[
                      _buildDeliveryAlertBadge(o)!,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. PRINTING & BILL BUTTONS (Point 5)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openPrintReceipt,
                    icon: const Icon(Icons.receipt, color: Colors.white, size: 18),
                    label: const Text('Customer Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openPrintStitchingSlip,
                    icon: const Icon(Icons.content_cut, color: Colors.white, size: 18),
                    label: const Text('Stitching Slip', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3. CUSTOMER DETAILS CARD
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
                    const Text('Customer Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey)),
                    const SizedBox(height: 8),
                    Text(custName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0F172A))),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(phone, style: TextStyle(color: Colors.grey.shade700, fontSize: 14)),
                    ],
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(address, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (phone.isNotEmpty) ...[
                          OutlinedButton.icon(
                            icon: const Icon(Icons.call, size: 16),
                            label: const Text('Call'),
                            onPressed: () => PhoneUtils.callCustomer(phone),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                            icon: const Icon(Icons.send, color: Colors.white, size: 16),
                            label: const Text('WhatsApp Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: _sendWhatsAppReceipt,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 4. ITEMS & MEASUREMENTS (Point 8)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Garments & 24 Measurements',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF0F172A))),
                // RE-ORDER / USE OLD MEASUREMENTS (Point 3)
                TextButton.icon(
                  onPressed: _useMeasurementsInNewOrder,
                  icon: const Icon(Icons.repeat, size: 16),
                  label: const Text('Naye Order Me Use Karein', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (items.isEmpty)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('Is order me koi item record nahi mila.')),
                ),
              )
            else
              ...items.map((it) {
                final cType = it['clothing_type'] ?? 'Custom Item';
                final qty = it['quantity'] ?? 1;
                final price = it['price'] ?? 0;
                final notes = (it['notes'] ?? '').toString();
                final itemPhotos = _extractItemPhotos(it);
                final meas = (it['measurements'] as Map<String, dynamic>?) ?? {};

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
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
                            Text('$cType (x$qty)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                            Text(currency.format(qty * price),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Notes: $notes', style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontStyle: FontStyle.italic)),
                        ],

                        // Photos attached
                        if (itemPhotos.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.photo_library, size: 14, color: Colors.blueGrey),
                              const SizedBox(width: 4),
                              Text('Photos (${itemPhotos.length}):',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: itemPhotos.length,
                              itemBuilder: (ctx, pIdx) {
                                final clean = itemPhotos[pIdx];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    onTap: () => _viewFullImage(clean),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: buildSmartImage(
                                          clean,
                                          fit: BoxFit.cover,
                                          width: 80,
                                          height: 80,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'MEASUREMENTS (24 BOXES)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5, color: Colors.blueGrey),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                final cust = Customer(
                                  id: o['customer_id'] ?? 0,
                                  name: o['customer_name'] ?? '',
                                  mobile: o['customer_mobile'] ?? '',
                                  address: o['customer_address'] ?? '',
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NewOrderScreen(
                                      preSelectedCustomer: cust,
                                      initialMeasurements: Map<String, dynamic>.from(meas),
                                      initialClothingType: cType,
                                      onOrderCreated: widget.onOrderUpdated,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.repeat, size: 14),
                              label: const Text('Yeh Naap Use Karein', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 6x4 Grid showing exact 24 boxes
                        MeasurementGrid(
                          staticValues: meas,
                          isReadOnly: true,
                        ),
                      ],
                    ),
                  ),
                );
              }),

            // Extra Order-level Photos (if not in items)
            Builder(
              builder: (ctx) {
                final allItemPhotos = <String>{};
                for (var it in items) {
                  allItemPhotos.addAll(_extractItemPhotos(it));
                }
                final orderOnlyPhotos = _extractOrderPhotos(o)
                    .where((p) => !allItemPhotos.contains(p))
                    .toList();

                if (orderOnlyPhotos.isEmpty) return const SizedBox.shrink();

                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.collections, size: 16, color: Color(0xFF0F172A)),
                            const SizedBox(width: 6),
                            Text('Order Photos (${orderOnlyPhotos.length})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: orderOnlyPhotos.length,
                            itemBuilder: (ctx, pIdx) {
                              final clean = orderOnlyPhotos[pIdx];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () => _viewFullImage(clean),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: buildSmartImage(
                                        clean,
                                        fit: BoxFit.cover,
                                        width: 80,
                                        height: 80,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // 5. PAYMENT BREAKDOWN
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Bill:'),
                        Text(currency.format(o['total_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if ((o['discount'] ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Discount:', style: TextStyle(color: Colors.green)),
                          Text('- ${currency.format(o['discount'])}',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Advance Paid:'),
                        Text(currency.format(o['advance_amount'] ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Baqaya (Balance Due):',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red)),
                        Text(currency.format(o['remaining_amount'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 6. PAYMENT HISTORY (IF ANY)
            if (payments.isNotEmpty) ...[
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
                      const Text('Payment History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      ...payments.map((p) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${p['payment_method'] ?? 'Cash'} • ${_formatShortDate(p['payment_date'])}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                              Text(currency.format(p['amount'] ?? 0),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // 7. ORDER ACTIONS (Complete, Partial, Deliver, Delete)
            const Text('Order Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _handleComplete,
                    child: const Text('Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _handlePartial,
                    child: const Text('Partial', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _handleDeliver,
                    child: const Text('Deliver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit Order', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _handleEditOrder,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('Delete Order', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _handleDelete,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String _formatShortDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return d.toString().split('T')[0];
    }
  }
}
