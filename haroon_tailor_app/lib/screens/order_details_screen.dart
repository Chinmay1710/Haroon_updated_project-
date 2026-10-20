import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';
import '../widgets/measurement_grid.dart';

class OrderDetailsScreen extends StatefulWidget {
  final int orderId;
  final VoidCallback? onOrderUpdated;

  const OrderDetailsScreen({super.key, required this.orderId, this.onOrderUpdated});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _order;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await ApiService.getOrderDetails(widget.orderId);
      setState(() {
        _order = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _updateStatus(String newStatus, {bool sendWhatsapp = false}) async {
    try {
      await ApiService.updateOrderStatus(
        orderId: widget.orderId,
        status: newStatus,
        sendWhatsapp: sendWhatsapp,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order status updated to $newStatus'), backgroundColor: Colors.green),
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

  void _handleDeliver() async {
    if (_order == null) return;
    final remaining = double.tryParse((_order!['remaining_amount'] ?? 0).toString()) ?? 0.0;
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (remaining > 0) {
      // Ask about remaining payment
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
                            onPressed: () {
                              Navigator.pop(ctx);
                              // Deliver without collecting now
                              _updateStatus('DELIVERED', sendWhatsapp: true);
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
                              Navigator.pop(ctx);
                              if (amt > 0) {
                                try {
                                  await ApiService.createPayment(
                                    orderId: widget.orderId,
                                    amount: amt,
                                    paymentMethod: payMethod,
                                    sendWhatsapp: true,
                                  );
                                } catch (_) {}
                              }
                              _updateStatus('DELIVERED', sendWhatsapp: true);
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
        _updateStatus('DELIVERED', sendWhatsapp: true);
      }
    }
  }

  void _handleDelete() async {
    if (_order == null) return;
    final billNo = _order!['order_number'] ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Order $billNo?'),
        content: Text(
          'Kya aap sach me order $billNo delete karna chahte hain?\n'
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

  void _sendWhatsAppReceipt() {
    if (_order == null) return;
    final phone = (_order!['customer_mobile'] ?? '').toString();
    final billNo = _order!['order_number'] ?? '';
    final custName = _order!['customer_name'] ?? '';
    final total = _order!['total_amount'] ?? 0;
    final remaining = _order!['remaining_amount'] ?? 0;

    final msg =
        'Assalam-o-Alaikum $custName ji,\n'
        'Haroon Tailor se aapka order details:\n'
        'Bill No: $billNo\n'
        'Total Amount: ₹$total\n'
        'Baqaya Rakam (Due): ₹$remaining\n'
        'Shukriya!';

    PhoneUtils.openWhatsApp(phone: phone, message: msg);
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
              child: Image.network(url, fit: BoxFit.contain),
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

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Order Details', style: TextStyle(color: Colors.white)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null || _order == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F172A),
          title: const Text('Order Details', style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_errorMessage ?? 'Order not found', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadOrder, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final o = _order!;
    final billNo = o['order_number'] ?? 'Bill-#${o['id']}';
    final status = (o['status'] ?? 'NEW').toString();
    final items = List<dynamic>.from(o['items'] ?? []);
    final payments = List<dynamic>.from(o['payments'] ?? []);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(billNo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Delete Order',
            onPressed: _handleDelete,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOrder,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. ORDER SUMMARY CARD
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 2. CUSTOMER CARD
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF0F172A).withOpacity(0.1),
                      child: const Icon(Icons.person, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o['customer_name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(o['customer_mobile'] ?? 'No phone',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.phone, color: Color(0xFF0F172A)),
                      onPressed: () async {
                        final phone = (o['customer_mobile'] ?? '').toString();
                        if (phone.isNotEmpty) {
                          final uri = Uri.parse('tel:$phone');
                          if (await canLaunchUrl(uri)) launchUrl(uri);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                      onPressed: _sendWhatsAppReceipt,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 3. ITEMS & 24 MEASUREMENTS (Point 8)
            const Text(
              'Kapde & 24 Naap Boxes (Measurements)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No items attached to order.'),
                ),
              )
            else
              ...items.map((item) {
                final cType = item['clothing_type'] ?? 'Custom Item';
                final qty = item['quantity'] ?? 1;
                final price = item['price'] ?? 0;
                final notes = item['notes'] ?? '';
                final meas = Map<String, dynamic>.from(item['measurements'] ?? {});
                final imagePath = (item['image_path'] ?? '').toString();

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
                        if (imagePath.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Photos:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 70,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: imagePath
                                  .split(',')
                                  .map((p) => p.trim())
                                  .where((p) => p.isNotEmpty)
                                  .map((url) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: InkWell(
                                    onTap: () => _viewFullImage(url),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        url,
                                        width: 70,
                                        height: 70,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 70,
                                          height: 70,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image, size: 24),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),
                        const Text('24 Naap Boxes (6x4):',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 6),

                        // 6x4 Measurement Grid for this item
                        MeasurementGrid(
                          staticValues: meas,
                          isReadOnly: true,
                        ),
                      ],
                    ),
                  ),
                );
              }),

            const SizedBox(height: 10),

            // 4. FINANCIAL SUMMARY
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

            // 5. PAYMENT HISTORY (IF ANY)
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

            // 6. ACTION BUTTONS (Point 3: Complete, Partial, Delete, Deliver)
            const Text('Order Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // Complete button
                if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle, color: Colors.white, size: 18),
                    label: const Text('Mark Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => _updateStatus('STITCHING_COMPLETE', sendWhatsapp: true),
                  ),

                // Partial button
                if (status != 'STITCHING_COMPLETE' && status != 'DELIVERED')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD97706)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.timelapse, color: Color(0xFFD97706), size: 18),
                    label: const Text('Partially Complete',
                        style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
                    onPressed: () => _updateStatus('PARTIALLY_COMPLETE', sendWhatsapp: true),
                  ),

                // Deliver button (with remaining payment prompt! Point 5)
                if (status != 'DELIVERED')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.local_shipping, color: Colors.white, size: 18),
                    label: const Text('Deliver Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _handleDeliver,
                  ),

                // WhatsApp Bill
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF25D366)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 18),
                  label: const Text('WhatsApp Bill', style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold)),
                  onPressed: _sendWhatsAppReceipt,
                ),

                // Delete button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                  label: const Text('Delete Order', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onPressed: _handleDelete,
                ),
              ],
            ),
            const SizedBox(height: 50),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  Widget _buildDateColumn(String title, dynamic dateStr, {bool isDelivery = false}) {
    String formatted = 'Not set';
    if (dateStr != null && dateStr.toString().isNotEmpty) {
      try {
        final d = DateTime.parse(dateStr.toString().split('T')[0]);
        formatted = DateFormat('dd MMM yyyy').format(d);
      } catch (_) {
        formatted = dateStr.toString();
      }
    }

    return Column(
      crossAxisAlignment: isDelivery ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(formatted, style: TextStyle(fontWeight: FontWeight.bold, color: isDelivery ? const Color(0xFF0F172A) : Colors.black87)),
      ],
    );
  }

  String _formatShortDate(dynamic dateStr) {
    if (dateStr == null) return '';
    try {
      final d = DateTime.parse(dateStr.toString().split('T')[0]);
      return DateFormat('dd/MM/yy').format(d);
    } catch (_) {
      return dateStr.toString();
    }
  }
}
