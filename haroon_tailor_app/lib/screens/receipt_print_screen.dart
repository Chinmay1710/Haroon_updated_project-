import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';
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
  String _shopAddress = '';
  String _shopPhone = '';
  String _paperSize = '80mm';
  final currency = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs. ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  bool _hasItems(Map<String, dynamic> o) {
    if (o.isEmpty) return false;
    if (o['items_detail'] is List && (o['items_detail'] as List).isNotEmpty) return true;
    if (o['raw_items'] is List && (o['raw_items'] as List).isNotEmpty) return true;
    if (o['items'] is List && (o['items'] as List).isNotEmpty) return true;
    return false;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final savedPaperSize = await LocalStorageService.getThermalPaperSize();
      Map<String, dynamic> o = {};

      // 1. Check detailed cache
      final cachedDetails = await LocalStorageService.getCachedOrderDetails(widget.orderId);
      if (cachedDetails != null && cachedDetails.isNotEmpty) {
        o = Map<String, dynamic>.from(cachedDetails);
      }

      // 2. Check full cached orders list
      if (!_hasItems(o)) {
        final allOrders = await LocalStorageService.getCachedOrders() ?? [];
        for (var ord in allOrders) {
          if (ord is Map) {
            final idStr = ord['id']?.toString() ?? '';
            final numStr = ord['order_number']?.toString() ?? '';
            final targetNum = widget.initialOrder != null ? widget.initialOrder!['order_number']?.toString() : null;
            if (idStr == widget.orderId.toString() ||
                numStr == 'Bill-${widget.orderId.toString().padLeft(6, '0')}' ||
                (targetNum != null && numStr == targetNum)) {
              final candidate = Map<String, dynamic>.from(ord);
              if (_hasItems(candidate) || o.isEmpty) {
                o = candidate;
              }
            }
          }
        }
      }

      // 3. Fallback to initialOrder
      if (widget.initialOrder != null) {
        final init = Map<String, dynamic>.from(widget.initialOrder!);
        if (o.isEmpty) {
          o = init;
        } else {
          init.forEach((k, v) {
            if (!o.containsKey(k) || o[k] == null || (o[k] is String && (o[k] as String).isEmpty)) {
              o[k] = v;
            }
          });
        }
      }

      // 4. Try ApiService if still empty
      if (!_hasItems(o)) {
        try {
          final fresh = await ApiService.getOrderDetails(widget.orderId);
          if (fresh.isNotEmpty) {
            o = Map<String, dynamic>.from(fresh);
          }
        } catch (_) {}
      }

      final settings = await ApiService.getShopSettings();
      if (mounted) {
        setState(() {
          _order = o;
          _shopName = settings['shop_name'] ?? 'Haroon Tailor';
          _shopAddress = settings['shop_address'] ?? settings['address'] ?? '';
          _shopPhone = settings['shop_phone'] ?? settings['phone'] ?? '';
          _paperSize = savedPaperSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load bill: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _extractItems() {
    List<dynamic>? rawList;
    if (_order['items_detail'] is List && (_order['items_detail'] as List).isNotEmpty) {
      rawList = _order['items_detail'] as List;
    } else if (_order['raw_items'] is List && (_order['raw_items'] as List).isNotEmpty) {
      rawList = _order['raw_items'] as List;
    } else if (_order['items'] is List && (_order['items'] as List).isNotEmpty) {
      rawList = _order['items'] as List;
    } else if (_order['items'] is String) {
      final str = (_order['items'] as String).trim();
      if (str.startsWith('[')) {
        try {
          final decoded = jsonDecode(str);
          if (decoded is List && decoded.isNotEmpty) rawList = decoded;
        } catch (_) {}
      }
    }

    final List<Map<String, dynamic>> result = [];
    if (rawList != null && rawList.isNotEmpty) {
      for (var elem in rawList) {
        if (elem is Map) {
          final itemMap = Map<String, dynamic>.from(elem);
          if (itemMap['clothing_type'] == null || itemMap['clothing_type'].toString().isEmpty) {
            itemMap['clothing_type'] = itemMap['name'] ?? itemMap['type'] ?? 'Custom';
          }
          result.add(itemMap);
        }
      }
    }

    // Fallback parsing from order summary string or total
    if (result.isEmpty) {
      final summary = (_order['items_summary'] ?? _order['items'] ?? 'Kapde').toString();
      final total = (_order['total_amount'] as num?)?.toDouble() ?? 0.0;
      final parts = summary.split(',');
      if (parts.length > 1) {
        final share = total / parts.length;
        for (var p in parts) {
          final clean = p.trim();
          if (clean.isNotEmpty) {
            result.add({
              'clothing_type': clean,
              'quantity': 1,
              'price': share,
            });
          }
        }
      } else {
        result.add({
          'clothing_type': summary.isNotEmpty ? summary : 'Custom Item',
          'quantity': (_order['quantity'] as num?)?.toInt() ?? 1,
          'price': total,
        });
      }
    }

    return result;
  }

  List<Map<String, dynamic>> _extractPayments() {
    if (_order['payments'] is List && (_order['payments'] as List).isNotEmpty) {
      return (_order['payments'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  Future<void> _printPdf() async {
    try {
      final is80mm = _paperSize == '80mm';
      final targetFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
      await Printing.layoutPdf(
        name: 'Bill_${_order['order_number'] ?? widget.orderId}.pdf',
        format: targetFormat,
        usePrinterSettings: true,
        onLayout: (PdfPageFormat format) async => _generatePdfReceipt(targetFormat),
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
      final is80mm = _paperSize == '80mm';
      final targetFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
      final pdfBytes = await _generatePdfReceipt(targetFormat);
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
    final total = (_order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final advance = (_order['advance_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (_order['remaining_amount'] as num?)?.toDouble() ?? (total - advance);
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final items = _extractItems();
    final itemsStr = items.map((i) => '${i['quantity'] ?? 1} ${i['clothing_type'] ?? 'Kapde'}').join(', ');

    final msg = await PhoneUtils.buildMessage(
      templateKey: 'new_order',
      customerName: custName,
      orderNumber: billNo,
      garments: itemsStr,
      deliveryDate: delivDate,
      totalAmount: total,
      advanceAmount: advance,
      balanceAmount: remaining,
      shopName: _shopName,
      shopPhone: _shopPhone,
    );

    await PhoneUtils.openWhatsApp(custMobile, msg);
  }

  Future<Uint8List> _generatePdfReceipt(PdfPageFormat format) async {
    final doc = pw.Document();
    final billNo = _order['order_number'] ?? '#${widget.orderId}';
    final custName = _order['customer_name'] ?? 'Walk-in';
    final custMobile = _order['customer_mobile'] ?? '';
    final orderDate = _order['order_date'] != null
        ? _order['order_date'].toString().split('T')[0]
        : DateFormat('dd/MM/yyyy').format(DateTime.now());
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final total = (_order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final advance = (_order['advance_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (_order['remaining_amount'] as num?)?.toDouble() ?? (total - advance);
    final items = _extractItems();
    final payments = _extractPayments();

    final bool is80mm = _paperSize == '80mm';
    final pageFormat = is80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
    final double hMargin = is80mm ? 6.0 : 4.0;
    final double titleSize = is80mm ? 13.0 : 11.0;
    final double subSize = is80mm ? 8.5 : 7.0;
    final double metaBoldSize = is80mm ? 10.0 : 8.5;
    final double metaSize = is80mm ? 9.0 : 7.5;
    final double totalSize = is80mm ? 11.0 : 8.5;
    final double dueSize = is80mm ? 12.0 : 9.0;
    final double footerSize = is80mm ? 8.5 : 7.0;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.symmetric(horizontal: hMargin, vertical: 4),
        build: (pw.Context context) {
          final subtitle = [
            if (_shopAddress.isNotEmpty) _shopAddress,
            if (_shopPhone.isNotEmpty) 'Ph: $_shopPhone',
          ].join(' • ');

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Shop Info Header
              pw.Center(
                child: pw.Text(
                  _shopName.toUpperCase(),
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: titleSize),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Center(
                  child: pw.Text(
                    subtitle,
                    style: pw.TextStyle(fontSize: subSize),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 2. Order & Customer Meta Rows
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('RECEIPT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: metaBoldSize)),
                  pw.Text('Bill: $billNo', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: metaBoldSize)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Date: $orderDate', style: pw.TextStyle(fontSize: metaSize)),
                  pw.Text('Due: $delivDate', style: pw.TextStyle(fontSize: metaSize)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cust: $custName', style: pw.TextStyle(fontSize: metaSize)),
                  if (custMobile.isNotEmpty)
                    pw.Text('Ph: $custMobile', style: pw.TextStyle(fontSize: metaSize)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 3. Items Header
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 5,
                    child: pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: metaSize)),
                  ),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Text('Qty', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: metaSize)),
                  ),
                  pw.Expanded(
                    flex: 3,
                    child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: metaSize)),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 4. Items Body
              ...items.map((it) {
                final cType = it['clothing_type'] ?? 'Custom';
                final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                final lineTotal = qty * price;
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 5,
                        child: pw.Text(cType, style: pw.TextStyle(fontSize: metaSize)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text('$qty', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: metaSize)),
                      ),
                      pw.Expanded(
                        flex: 3,
                        child: pw.Text('Rs. ${lineTotal.toStringAsFixed(0)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: metaSize)),
                      ),
                    ],
                  ),
                );
              }),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 5. TOTAL & Payments
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: totalSize)),
                  pw.Text('Rs. ${total.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: totalSize)),
                ],
              ),

              if (payments.isNotEmpty) ...[
                ...payments.map((p) {
                  final pDate = p['payment_date'] != null ? p['payment_date'].toString().split('T')[0] : '';
                  final pAmt = (p['amount'] as num?)?.toDouble() ?? 0.0;
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Paid ($pDate):', style: pw.TextStyle(fontSize: subSize)),
                      pw.Text('-Rs. ${pAmt.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: subSize)),
                    ],
                  );
                }),
              ] else if (advance > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Paid (Advance):', style: pw.TextStyle(fontSize: subSize)),
                    pw.Text('-Rs. ${advance.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: subSize)),
                  ],
                ),
              ],

              // 6. DUE Balance
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DUE BALANCE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: dueSize)),
                  pw.Text('Rs. ${remaining.toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: dueSize)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.6, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 3),

              // 7. Footer
              pw.Center(
                child: pw.Text(
                  'Thank you for your business!',
                  style: pw.TextStyle(fontSize: footerSize),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 20),
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
    final orderDate = _order['order_date'] != null
        ? _order['order_date'].toString().split('T')[0]
        : DateFormat('dd/MM/yyyy').format(DateTime.now());
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final total = (_order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final advance = (_order['advance_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (_order['remaining_amount'] as num?)?.toDouble() ?? (total - advance);
    final items = _extractItems();
    final payments = _extractPayments();

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
                  // Paper Size Selector Toggle (80mm vs 58mm)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment<String>(
                          value: '80mm',
                          icon: Icon(Icons.print, size: 18),
                          label: Text('80mm (3-Inch Bada Roll)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        ButtonSegment<String>(
                          value: '58mm',
                          icon: Icon(Icons.receipt, size: 18),
                          label: Text('58mm (2-Inch)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                      selected: {_paperSize},
                      onSelectionChanged: (Set<String> newSelection) async {
                        final chosen = newSelection.first;
                        setState(() => _paperSize = chosen);
                        await LocalStorageService.saveThermalPaperSize(chosen);
                      },
                    ),
                  ),

                  // Exact Thermal Receipt Paper Preview matching Website
                  Center(
                    child: Container(
                      width: _paperSize == '80mm' ? 380 : 300,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Compact Shop Info Header
                          Text(
                            _shopName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
                          ),
                          if (_shopAddress.isNotEmpty || _shopPhone.isNotEmpty)
                            Text(
                              [
                                if (_shopAddress.isNotEmpty) _shopAddress,
                                if (_shopPhone.isNotEmpty) 'Ph: $_shopPhone',
                              ].join(' • '),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 4),

                          // 2. Receipt & Order Rows
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('RECEIPT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                              Text('Bill: $billNo', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Date: $orderDate', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                              Text('Due: $delivDate', style: const TextStyle(fontSize: 12, color: Colors.black)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Cust: $custName', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                              if (custMobile.isNotEmpty)
                                Text('Ph: $custMobile', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 4),

                          // 3. Items Header (50% / 15% / 35%)
                          Row(
                            children: const [
                              Expanded(flex: 5, child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 2, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              Expanded(flex: 3, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _buildDashedLine(),
                          const SizedBox(height: 4),

                          // 4. Items Body
                          ...items.map((it) {
                            final cType = it['clothing_type'] ?? 'Custom';
                            final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                            final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                            final lineTotal = qty * price;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(flex: 5, child: Text(cType, style: const TextStyle(fontSize: 12))),
                                  Expanded(flex: 2, child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                                  Expanded(flex: 3, child: Text(currency.format(lineTotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 4),

                          // 5. Total & Paid
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                              Text(currency.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                            ],
                          ),
                          if (payments.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            ...payments.map((p) {
                              final pDate = p['payment_date'] != null ? p['payment_date'].toString().split('T')[0] : '';
                              final pAmt = (p['amount'] as num?)?.toDouble() ?? 0.0;
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Paid ($pDate):', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                  Text('- ${currency.format(pAmt)}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                ],
                              );
                            }),
                          ] else if (advance > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Paid (Advance):', style: TextStyle(fontSize: 11, color: Colors.black87)),
                                Text('- ${currency.format(advance)}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                              ],
                            ),
                          ],
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('DUE BALANCE:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black)),
                              Text(currency.format(remaining), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _buildDashedLine(),
                          const SizedBox(height: 6),

                          // 6. Footer
                          const Text(
                            'Thank you for your business!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.black54),
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
              height: 1.5,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
            ),
          ),
        );
      },
    );
  }
}
