import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../utils/phone_utils.dart';

class ReceiptPrintScreen extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic>? initialOrder;

  const ReceiptPrintScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  @override
  State<ReceiptPrintScreen> createState() => _ReceiptPrintScreenState();
}

class _ReceiptPrintScreenState extends State<ReceiptPrintScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _order = {};
  String _shopName = 'Haroon Tailor';
  final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> o;
      if (widget.initialOrder != null && widget.initialOrder!['items'] is List) {
        o = widget.initialOrder!;
      } else {
        o = await ApiService.getOrderDetails(widget.orderId);
      }
      final settings = await ApiService.getShopSettings();
      setState(() {
        _order = o;
        _shopName = settings['shop_name'] ?? 'Haroon Tailor';
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load bill: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printPdf() async {
    try {
      await Printing.layoutPdf(
        name: 'Bill_${_order['order_number'] ?? widget.orderId}.pdf',
        onLayout: (PdfPageFormat format) async => _generatePdfReceipt(format),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    try {
      final pdfBytes = await _generatePdfReceipt(PdfPageFormat.roll57);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Bill_${_order['order_number'] ?? widget.orderId}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendWhatsAppBill() async {
    final custMobile = _order['customer_mobile'] ?? '';
    final custName = _order['customer_name'] ?? 'Grahak';
    final billNo = _order['order_number'] ?? '#${widget.orderId}';
    final total = _order['total_amount'] ?? 0;
    final advance = _order['advance_amount'] ?? 0;
    final remaining = _order['remaining_amount'] ?? 0;
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';

    final msg =
        'Assalam-o-Alaikum $custName ji,\n'
        '$_shopName ko chunne ke liye shukriya!\n\n'
        'Aapka Order $billNo safaltapoorvak darj kar liya gaya hai.\n\n'
        '👔 Total Bill: Rs. $total\n'
        '💵 Jama Rakam: Rs. $advance\n'
        '⏳ Baqaya Rakam: Rs. $remaining\n'
        '📅 Delivery Date: $delivDate\n\n'
        'Note: Jummah (Friday) ko dukan band rehti hai.\n\n'
        'Shukriya!\n$_shopName';

    await PhoneUtils.openWhatsApp(custMobile, msg);
  }

  Future<Uint8List> _generatePdfReceipt(PdfPageFormat format) async {
    final doc = pw.Document();
    final billNo = _order['order_number'] ?? '#${widget.orderId}';
    final custName = _order['customer_name'] ?? 'Walk-in';
    final custMobile = _order['customer_mobile'] ?? '';
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final total = _order['total_amount'] ?? 0;
    final remaining = _order['remaining_amount'] ?? 0;
    final dynamic rawItems = _order['items'];
    final List<dynamic> items = rawItems is List ? rawItems : [];
    final payments = (_order['payments'] as List<dynamic>?) ?? [];
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    // 58mm thermal roll format
    final pageFormat = PdfPageFormat.roll57;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(6),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  _shopName.toUpperCase(),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                ),
              ),
              pw.Center(
                child: pw.Text('CUSTOMER RECEIPT', style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No: $billNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(nowStr, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Text('Customer: $custName', style: const pw.TextStyle(fontSize: 9)),
              if (custMobile.isNotEmpty)
                pw.Text('Phone: $custMobile', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Delivery: $delivDate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Qty', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              ...items.map((it) {
                final cType = it['clothing_type'] ?? 'Custom';
                final qty = it['quantity'] ?? 1;
                final price = it['price'] ?? 0;
                final lineTotal = qty * price;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(child: pw.Text(cType, style: const pw.TextStyle(fontSize: 8))),
                      pw.Text('$qty', style: const pw.TextStyle(fontSize: 8)),
                      pw.SizedBox(width: 20),
                      pw.Text('Rs. $lineTotal', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Bill:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('Rs. $total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ],
              ),
              if (payments.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                ...payments.map((p) {
                  final pDate = p['payment_date'] != null
                      ? p['payment_date'].toString().split('T')[0]
                      : '';
                  final pAmt = p['amount'] ?? 0;
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Paid ($pDate):', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('-Rs. $pAmt', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  );
                }),
              ],
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Balance Due (Baqaya):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text('Rs. $remaining', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.Center(
                child: pw.Text(
                  'Note: Jummah (Friday) ko dukan band rehti hai.',
                  style: const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Thank you! Visit Again.',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final billNo = _order['order_number'] ?? '#${widget.orderId}';
    final custName = _order['customer_name'] ?? 'Walk-in';
    final custMobile = _order['customer_mobile'] ?? '';
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final total = _order['total_amount'] ?? 0;
    final remaining = _order['remaining_amount'] ?? 0;
    final dynamic rawItems = _order['items'];
    final List<dynamic> items = rawItems is List ? rawItems : [];
    final payments = (_order['payments'] as List<dynamic>?) ?? [];
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: Text('Customer Bill ($billNo)'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: _sharePdf,
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Bill',
            onPressed: _printPdf,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Thermal Receipt Paper Preview
                  Center(
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _shopName.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'CUSTOMER RECEIPT / BILL',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          _buildDashedLine(),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Bill No: $billNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(nowStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Customer: $custName', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          if (custMobile.isNotEmpty)
                            Text('Phone: $custMobile', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                          Text('Due Date: $delivDate', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                          const SizedBox(height: 10),
                          _buildDashedLine(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Expanded(child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              SizedBox(width: 30),
                              Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 8),
                          if (items.isEmpty)
                            const Text('1x Custom Item', style: TextStyle(fontSize: 13))
                          else
                            ...items.map((it) {
                              final cType = it['clothing_type'] ?? 'Custom';
                              final qty = it['quantity'] ?? 1;
                              final price = it['price'] ?? 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text(cType, style: const TextStyle(fontSize: 13))),
                                    Text('$qty', style: const TextStyle(fontSize: 13)),
                                    SizedBox(
                                      width: 80,
                                      child: Text(
                                        currency.format(qty * price),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          const SizedBox(height: 10),
                          _buildDashedLine(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total Bill:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(currency.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                          if (payments.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...payments.map((p) {
                              final pDate = p['payment_date'] != null
                                  ? p['payment_date'].toString().split('T')[0]
                                  : '';
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 1.5),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Paid ($pDate):', style: TextStyle(fontSize: 12, color: Colors.green.shade800)),
                                    Text('- ${currency.format(p['amount'] ?? 0)}',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                                  ],
                                ),
                              );
                            }),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Baqaya (Balance Due):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
                              Text(
                                currency.format(remaining),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: remaining > 0 ? Colors.red : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildDashedLine(),
                          const SizedBox(height: 10),
                          Text(
                            'Note: Jummah (Friday) ko dukan band rehti hai.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Shukriya! Phir zaroor tashreef layein.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _printPdf,
                          icon: const Icon(Icons.print, color: Colors.white),
                          label: const Text('Print Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _sendWhatsAppBill,
                          icon: const Icon(Icons.send, color: Colors.white),
                          label: const Text('WhatsApp Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDashedLine() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 6).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => const SizedBox(
              width: 3,
              height: 1,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.black45)),
            ),
          ),
        );
      },
    );
  }
}
