import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  final doc = pw.Document();
  final is80mm = true;
  
  // Custom exact 80mm paper roll format with zero internal driver margin
  final pageFormat = PdfPageFormat(
    (is80mm ? 80.0 : 58.0) * PdfPageFormat.mm,
    double.infinity,
    marginAll: 0,
  );

  final meas = {
    '1': '36',
    '2': '38',
    '3': '28//',
    '4': '21',
    '5': '15//',
    '8': '42//',
    '15': '26',
    '16': '9//',
    '22': '18//',
  };

  String getBoxValue(Map m, int boxNum) {
    return m['$boxNum'] ?? '';
  }

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.symmetric(horizontal: 2.5 * PdfPageFormat.mm, vertical: 4),
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                'STITCHING SLIP',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Center(
              child: pw.Text(
                'Haroon Tailor',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 2),

            pw.SizedBox(
              width: double.infinity,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Bill No:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('Bill-000001', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
            pw.SizedBox(
              width: double.infinity,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Due:', style: const pw.TextStyle(fontSize: 10.5)),
                  pw.Text('22 Nov 2026', style: const pw.TextStyle(fontSize: 10.5)),
                ],
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 2),

            pw.Text('Garments:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
            pw.Text('Pant (x1)', style: const pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 2),
            pw.Text('Item Note: STREET PRESS, BUTTOM HAT SILI, 1 POCKET', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 3),
            pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 2),

            pw.Center(
              child: pw.Text(
                'MEASUREMENTS',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11.5),
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              'Pant - Bill-000001',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                decoration: pw.TextDecoration.underline,
              ),
            ),
            pw.SizedBox(height: 4),

            // Measurements Grid: 4 columns x 6 rows
            pw.SizedBox(
              width: double.infinity,
              child: pw.Table(
                border: pw.TableBorder.all(width: 1.2, color: PdfColors.black),
                tableWidth: pw.TableWidth.max,
                defaultColumnWidth: const pw.FlexColumnWidth(1),
                columnWidths: const {
                  0: pw.FlexColumnWidth(1),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1),
                  3: pw.FlexColumnWidth(1),
                },
                children: List.generate(6, (r) {
                  return pw.TableRow(
                    children: List.generate(4, (c) {
                      final sidewaysRow = 3 - c;
                      final sidewaysCol = r;
                      final boxNum = sidewaysRow * 6 + sidewaysCol + 1;
                      final val = getBoxValue(meas, boxNum);
                      return pw.Container(
                        height: 38,
                        alignment: pw.Alignment.center,
                        child: val.isNotEmpty
                            ? pw.Transform.rotateBox(
                                angle: -1.5707963267948966, // -90 deg
                                child: pw.Text(
                                  val,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: val.length > 5 ? 11.0 : (val.length > 3 ? 13.0 : 15.0),
                                    color: PdfColors.black,
                                  ),
                                ),
                              )
                            : pw.SizedBox(),
                      );
                    }),
                  );
                }),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed),
            pw.SizedBox(height: 3),

            pw.SizedBox(
              width: double.infinity,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cut By: _____', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text('Sewn By: _____', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(height: 4),

            pw.Center(
              child: pw.Text(
                'Generated: 11 Nov 2026 - 15:55:53',
                style: const pw.TextStyle(fontSize: 8.5),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.SizedBox(height: 25),
          ],
        );
      },
    ),
  );

  final bytes = await doc.save();
  final f = File('/tmp/test_slip.pdf');
  await f.writeAsBytes(bytes);
  print('Saved /tmp/test_slip.pdf with ${bytes.length} bytes');
}

