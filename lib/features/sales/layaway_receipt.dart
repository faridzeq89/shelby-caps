import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class LayawayReceiptLine {
  const LayawayReceiptLine(this.description, this.qty, this.lineTotalCents);
  final String description;
  final int qty;
  final int lineTotalCents;
}

/// Comprobante de apartado (formato rollo 80mm): piezas, total, pagado, saldo y
/// fecha límite.
class LayawayReceiptService {
  const LayawayReceiptService._();

  static String _m(int c) => '\$${(c / 100).toStringAsFixed(2)}';

  static Future<Uint8List> build({
    required String folio,
    required String customerName,
    required DateTime dateTime,
    required List<LayawayReceiptLine> lines,
    required int totalCents,
    required int paidCents,
    required int balanceCents,
    required DateTime dueDate,
    String businessName = 'Montana Boutique',
  }) async {
    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy');

    pw.Widget row(String a, String b, {bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(a,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(b,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
              child: pw.Text(businessName,
                  style:
                      pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
          pw.Center(
              child: pw.Text('COMPROBANTE DE APARTADO',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Text('Folio: $folio', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Cliente: $customerName',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Fecha: ${df.format(dateTime)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          for (final l in lines)
            row('${l.qty} x ${l.description}', _m(l.lineTotalCents)),
          pw.Divider(),
          row('Total', _m(totalCents)),
          row('Pagado', _m(paidCents)),
          row('SALDO', _m(balanceCents), bold: true),
          pw.SizedBox(height: 4),
          pw.Text('Fecha límite: ${df.format(dueDate)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Center(
              child: pw.Text('Conserve este comprobante',
                  style: const pw.TextStyle(fontSize: 8))),
        ],
      ),
    ));
    return doc.save();
  }
}
