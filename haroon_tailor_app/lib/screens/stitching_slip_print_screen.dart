import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/api_service.dart';
import '../services/local_storage_service.dart';

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

  bool _hasMeasurements(Map<String, dynamic> o) {
    if (o.isEmpty) return false;
    if (o['items_detail'] is List && (o['items_detail'] as List).isNotEmpty) {
      for (var it in o['items_detail']) {
        if (it is Map && it['measurements'] is Map && (it['measurements'] as Map).isNotEmpty) {
          return true;
        }
      }
    }
    if (o['measurements'] is Map && (o['measurements'] as Map).isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> o = {};

      // 1. Check detailed cache in local storage
      final cachedDetails = await LocalStorageService.getCachedOrderDetails(widget.orderId);
      if (cachedDetails != null && cachedDetails.isNotEmpty) {
        o = Map<String, dynamic>.from(cachedDetails);
      }

      // 2. Check full cached orders list
      if (!_hasMeasurements(o)) {
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
              if (_hasMeasurements(candidate) || o.isEmpty) {
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

      // 4. Try ApiService if still empty or missing measurements
      if (!_hasMeasurements(o)) {
        try {
          final fresh = await ApiService.getOrderDetails(widget.orderId);
          if (fresh.isNotEmpty) {
            o = Map<String, dynamic>.from(fresh);
          }
        } catch (_) {}
      }

      // 5. If items have empty measurements, fall back to customer's offline naap history
      final custId = (o['customer_id'] as num?)?.toInt() ?? 0;
      if (custId > 0) {
        final items = _extractItemsFrom(o);
        bool anyMissing = items.any((it) => (it['measurements'] as Map).isEmpty);
        if (anyMissing) {
          final custNaaps = await LocalStorageService.getCustomerMeasurementsOffline(custId);
          if (custNaaps.isNotEmpty) {
            for (var it in items) {
              if ((it['measurements'] as Map).isEmpty) {
                final cType = (it['clothing_type'] ?? '').toString().toLowerCase();
                final match = custNaaps.firstWhere(
                  (p) => (p['template_type'] ?? '').toString().toLowerCase() == cType,
                  orElse: () => custNaaps.first,
                );
                if (match['values'] is Map) {
                  it['measurements'] = Map<String, dynamic>.from(match['values'] as Map);
                }
              }
            }
            o['items_detail'] = items;
          }
        }
      }

      final settings = await ApiService.getShopSettings();
      if (mounted) {
        setState(() {
          _order = o;
          _shopName = settings['shop_name'] ?? 'Haroon Tailor';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load slip: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _extractItemsFrom(Map<String, dynamic> order) {
    List<dynamic>? rawList;
    if (order['items_detail'] is List && (order['items_detail'] as List).isNotEmpty) {
      rawList = order['items_detail'] as List;
    } else if (order['raw_items'] is List && (order['raw_items'] as List).isNotEmpty) {
      rawList = order['raw_items'] as List;
    } else if (order['items'] is List && (order['items'] as List).isNotEmpty) {
      rawList = order['items'] as List;
    } else if (order['items'] is String) {
      final str = (order['items'] as String).trim();
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
            itemMap['clothing_type'] = itemMap['name'] ?? itemMap['type'] ?? 'Kapda';
          }
          if (itemMap['measurements'] is String) {
            try {
              itemMap['measurements'] = jsonDecode(itemMap['measurements'] as String);
            } catch (_) {
              itemMap['measurements'] = {};
            }
          }
          if (itemMap['measurements'] == null || itemMap['measurements'] is! Map) {
            if (order['measurements'] is Map) {
              itemMap['measurements'] = Map<String, dynamic>.from(order['measurements'] as Map);
            } else {
              itemMap['measurements'] = {};
            }
          }
          result.add(itemMap);
        }
      }
    }

    // If still empty, build from order-level summary/measurements
    if (result.isEmpty) {
      Map<String, dynamic> rootMeas = {};
      if (order['measurements'] is Map) {
        rootMeas = Map<String, dynamic>.from(order['measurements'] as Map);
      } else if (order['measurements'] is String) {
        try {
          final dec = jsonDecode(order['measurements'] as String);
          if (dec is Map) rootMeas = Map<String, dynamic>.from(dec);
        } catch (_) {}
      }

      final summary = (order['items_summary'] ?? order['items'] ?? 'Kapda').toString();
      final parts = summary.split(',');
      if (parts.length > 1) {
        for (var part in parts) {
          final cleanPart = part.trim();
          if (cleanPart.isNotEmpty) {
            result.add({
              'clothing_type': cleanPart,
              'quantity': 1,
              'price': 0.0,
              'notes': (order['notes'] ?? '').toString(),
              'measurements': rootMeas,
            });
          }
        }
      } else {
        result.add({
          'clothing_type': summary.isNotEmpty ? summary : 'Kapda',
          'quantity': (order['quantity'] as num?)?.toInt() ?? 1,
          'price': (order['total_amount'] as num?)?.toDouble() ?? 0.0,
          'notes': (order['notes'] ?? '').toString(),
          'measurements': rootMeas,
        });
      }
    }

    return result;
  }

  String _getBoxValue(Map measurements, int boxNum) {
    final keys = [
      'Box $boxNum',
      'box_$boxNum',
      'Box$boxNum',
      '$boxNum',
      boxNum,
      'b$boxNum',
      'B$boxNum',
    ];
    for (var k in keys) {
      if (measurements.containsKey(k)) {
        final v = measurements[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
    }
    return '';
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
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final items = _extractItemsFrom(_order);
    final nowStr = DateFormat('dd/MM/yyyy - hh:mm:ss a').format(DateTime.now());

    final pageFormat = PdfPageFormat.roll57;

    // Single continuous page for thermal roll printing (Continuous paper roll, all garments together!)
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // 1. Header (STITCHING SLIP - Haroon Tailor)
              pw.Center(
                child: pw.Text(
                  'STITCHING SLIP',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  _shopName,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 2. Order Details (Note 1: NO CUSTOMER NAME)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(billNo, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Delivery Due:', style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text(delivDate, style: const pw.TextStyle(fontSize: 8.5)),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 2),

              // 3. Garments Loop (Note 2: Separate block for each clothing type, printed CONTINUOUSLY!)
              ...items.map((it) {
                final cType = it['clothing_type'] ?? 'Custom Item';
                final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                final notes = (it['notes'] ?? '').toString().trim();
                final meas = (it['measurements'] as Map<String, dynamic>?) ?? {};

                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // Garment type header
                    pw.Text('Garments:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                    pw.Text('$cType (x$qty)', style: const pw.TextStyle(fontSize: 8.5)),
                    if (notes.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('Item Note: $notes', style: const pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                    ],
                    pw.SizedBox(height: 3),
                    pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                    pw.SizedBox(height: 2),

                    // Measurements Header
                    pw.Center(
                      child: pw.Text(
                        'MEASUREMENTS',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      '$cType - $billNo',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 8.5,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    pw.SizedBox(height: 3),

                    // Horizontal 4 columns x 6 rows Measurements Grid (Rotated 2 times clockwise / 180 deg)
                    pw.Table(
                      border: pw.TableBorder.all(width: 0.8, color: PdfColors.black),
                      children: List.generate(6, (r) {
                        return pw.TableRow(
                          children: List.generate(4, (c) {
                            final boxNum = c * 6 + (5 - r) + 1;
                            final val = _getBoxValue(meas, boxNum);
                            return pw.Container(
                              height: 26,
                              alignment: pw.Alignment.center,
                              child: val.isNotEmpty
                                  ? pw.Transform.rotateBox(
                                      angle: -1.5707963267948966, // 270 deg clockwise (-90 deg)
                                      child: pw.Text(
                                        val,
                                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                                      ),
                                    )
                                  : pw.SizedBox(),
                            );
                          }),
                        );
                      }),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                    pw.SizedBox(height: 3),
                  ],
                );
              }),

              // 4. Sign-offs at end of continuous roll
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cut By: _____', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Sewn By: _____', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 4),

              // 5. Generated Timestamp
              pw.Center(
                child: pw.Text(
                  'Generated: $nowStr',
                  style: const pw.TextStyle(fontSize: 6.5),
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
    final delivDate = _order['delivery_date'] != null
        ? _order['delivery_date'].toString().split('T')[0]
        : '-';
    final items = _extractItemsFrom(_order);
    final nowStr = DateFormat('dd/MM/yyyy - hh:mm:ss a').format(DateTime.now());

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
                  // Exact Continuous Thermal Slip matching Website
                  Center(
                    child: Container(
                      width: 320,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                          // 1. Header
                          const Text(
                            'STITCHING SLIP',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black),
                          ),
                          Text(
                            _shopName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                          ),
                          const SizedBox(height: 8),
                          _buildDashedLine(),
                          const SizedBox(height: 6),

                          // 2. Order Details (Note 1: NO CUSTOMER NAME)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bill No:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text(billNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Delivery Due:', style: TextStyle(fontSize: 13)),
                              Text(delivDate, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _buildDashedLine(),
                          const SizedBox(height: 6),

                          // 3. Garments Loop (Note 2: Separate block for each clothing type, printed CONTINUOUSLY!)
                          ...items.map((it) {
                            final cType = it['clothing_type'] ?? 'Custom Item';
                            final qty = (it['quantity'] as num?)?.toInt() ?? 1;
                            final notes = (it['notes'] ?? '').toString().trim();
                            final meas = (it['measurements'] as Map<String, dynamic>?) ?? {};

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Garments:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('$cType (x$qty)', style: const TextStyle(fontSize: 13)),
                                if (notes.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text('Item Note: $notes', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                                ],
                                const SizedBox(height: 8),
                                _buildDashedLine(),
                                const SizedBox(height: 6),

                                // Measurements Header
                                const Text(
                                  'MEASUREMENTS',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$cType - $billNo',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const SizedBox(height: 6),

                                // Horizontal 4 columns x 6 rows Measurements Grid (Rotated 2 times clockwise / 180 deg)
                                Table(
                                  border: TableBorder.all(color: Colors.black, width: 1.0),
                                  columnWidths: const {
                                    0: FlexColumnWidth(1),
                                    1: FlexColumnWidth(1),
                                    2: FlexColumnWidth(1),
                                    3: FlexColumnWidth(1),
                                  },
                                  children: List.generate(6, (r) {
                                    return TableRow(
                                      children: List.generate(4, (c) {
                                        final boxNum = c * 6 + (5 - r) + 1;
                                        final val = _getBoxValue(meas, boxNum);
                                        return Container(
                                          height: 48,
                                          alignment: Alignment.center,
                                          color: Colors.white,
                                          child: val.isNotEmpty
                                              ? RotatedBox(
                                                  quarterTurns: 3, // 270 deg clockwise
                                                  child: Text(
                                                    val,
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                )
                                              : const SizedBox(),
                                        );
                                      }),
                                    );
                                  }),
                                ),
                                const SizedBox(height: 8),
                                _buildDashedLine(),
                                const SizedBox(height: 6),
                              ],
                            );
                          }),

                          // 4. Sign-offs
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Text('Cut By: _____', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text('Sewn By: _____', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 5. Timestamp
                          Text(
                            'Generated: $nowStr',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 9, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

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
              height: 1.5,
              child: DecoratedBox(decoration: BoxDecoration(color: Colors.black)),
            ),
          ),
        );
      },
    );
  }
}
