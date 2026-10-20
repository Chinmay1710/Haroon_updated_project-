import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';

class StitchingSlipPrintScreen extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic>? initialOrder;

  const StitchingSlipPrintScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  @override
  State<StitchingSlipPrintScreen> createState() => _StitchingSlipPrintScreenState();
}

class _StitchingSlipPrintScreenState extends State<StitchingSlipPrintScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _order = {};
  String _shopName = 'Haroon Tailor';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final o = widget.initialOrder ?? await ApiService.getOrderDetails(widget.orderId);
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
          SnackBar(content: Text('Failed to load slip: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printPdf() async {
    try {
      await Printing.layoutPdf(
        name: 'Stitching_Slip_${_order['order_number'] ?? widget.orderId}.pdf',
        onLayout: (PdfPageFormat format) async => _generatePdfSlip(format),
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
      final pdfBytes = await _generatePdfSlip(PdfPageFormat.roll57);
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'Stitching_Slip_${_order['order_number'] ?? widget.orderId}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Uint8List> _generatePdfSlip(PdfPageFormat format) async {
    final doc = pw.Document();
    final billNo = _order['order_number'] ?? '#${widget.orderId}';
    final custName = _order['customer_name'] ?? 'Customer';
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final items = (_order['items'] as List<dynamic>?) ?? [];
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    // Roll 58mm
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
                  'STITCHING SLIP',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                ),
              ),
              pw.Center(
                child: pw.Text(_shopName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text(billNo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Delivery Due:', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(delivDate, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Text('Customer: $custName', style: const pw.TextStyle(fontSize: 9)),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),

              // Items & Measurements
              ...items.map((it) {
                final cType = it['clothing_type'] ?? 'Custom';
                final qty = it['quantity'] ?? 1;
                final notes = (it['notes'] ?? '').toString();
                final meas = (it['measurements'] as Map<String, dynamic>?) ?? {};

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Garment: $cType (x$qty)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    if (notes.isNotEmpty)
                      pw.Text('Notes: $notes', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                    pw.SizedBox(height: 4),
                    pw.Center(
                      child: pw.Text('MEASUREMENTS (24 BOXES)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    ),
                    pw.SizedBox(height: 3),

                    // 6 Columns x 4 Rows table
                    pw.Table(
                      border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
                      children: List.generate(4, (rowIndex) {
                        return pw.TableRow(
                          children: List.generate(6, (colIndex) {
                            final boxNum = (rowIndex * 6) + colIndex + 1;
                            final val = (meas['Box $boxNum'] ?? '').toString().trim();
                            return pw.Container(
                              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 1),
                              alignment: pw.Alignment.center,
                              child: pw.Column(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Text('$boxNum', style: const pw.TextStyle(fontSize: 5, color: PdfColors.grey700)),
                                  pw.Text(
                                    val.isNotEmpty ? val : '-',
                                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }),
                        );
                      }),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                  ],
                );
              }),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cut By: _______', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Sewn By: _______', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(nowStr, style: const pw.TextStyle(fontSize: 7)),
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
    final custName = _order['customer_name'] ?? 'Customer';
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final items = (_order['items'] as List<dynamic>?) ?? [];
    final nowStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());

    return Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      appBar: AppBar(
        title: Text('Stitching Slip ($billNo)'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share Slip',
            onPressed: _sharePdf,
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'Print Slip',
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
                  // Thermal Karigar Slip Preview
                  Center(
                    child: Container(
                      width: 340,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
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
                          const Text(
                            'STITCHING SLIP (KARIGAR)',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                          ),
                          Text(
                            _shopName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                          ),
                          const SizedBox(height: 10),
                          _buildDashedLine(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bill No:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(billNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Delivery Due:', style: TextStyle(fontSize: 13)),
                              Text(delivDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                            ],
                          ),
                          Text('Customer: $custName', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _buildDashedLine(),
                          const SizedBox(height: 8),

                          if (items.isEmpty)
                            const Text('No items in order', textAlign: TextAlign.center)
                          else
                            ...items.map((it) {
                              final cType = it['clothing_type'] ?? 'Custom';
                              final qty = it['quantity'] ?? 1;
                              final notes = (it['notes'] ?? '').toString();
                              final meas = (it['measurements'] as Map<String, dynamic>?) ?? {};

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Garment: $cType (x$qty)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                  ),
                                  if (notes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                                      child: Text(
                                        'Note: $notes',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    color: const Color(0xFF0F172A),
                                    child: const Text(
                                      'MEASUREMENTS (24 BOXES)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 6),

                                  // 6 Columns x 4 Rows = 24 Boxes
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: 24,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 6,
                                      crossAxisSpacing: 3,
                                      mainAxisSpacing: 3,
                                      childAspectRatio: 0.95,
                                    ),
                                    itemBuilder: (context, idx) {
                                      final boxNum = idx + 1;
                                      final val = (meas['Box $boxNum'] ?? '').toString().trim();
                                      final hasVal = val.isNotEmpty;

                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.black87, width: 1),
                                          color: hasVal ? const Color(0xFFF1F5F9) : Colors.white,
                                        ),
                                        child: Stack(
                                          children: [
                                            Positioned(
                                              top: 1,
                                              left: 2,
                                              child: Text(
                                                '$boxNum',
                                                style: const TextStyle(fontSize: 7, color: Colors.black54, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Center(
                                              child: Padding(
                                                padding: const EdgeInsets.only(top: 5),
                                                child: Text(
                                                  val,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                    color: Colors.black,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  _buildDashedLine(),
                                  const SizedBox(height: 8),
                                ],
                              );
                            }),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('Cut By: _______', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text('Sewn By: _______', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            nowStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bottom Print Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _printPdf,
                      icon: const Icon(Icons.print, color: Colors.white),
                      label: const Text('Print Stitching Slip (Karigar)',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
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
