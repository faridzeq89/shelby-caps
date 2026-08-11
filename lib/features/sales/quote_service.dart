import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'ticket_service.dart';

class QuotePdfLine {
  const QuotePdfLine(this.description, this.qty, this.unitPriceCents,
      this.lineTotalCents);
  final String description;
  final int qty;
  final int unitPriceCents;
  final int lineTotalCents;
}

/// PDF de cotización (formato rollo 80mm, como el ticket) para compartir por
/// WhatsApp o imprimir: piezas, precios, total y vigencia.
class QuoteService {
  const QuoteService._();

  static String _m(int c) => '\$${(c / 100).toStringAsFixed(2)}';

  static Future<Uint8List> build({
    required String folio,
    required DateTime dateTime,
    required List<QuotePdfLine> lines,
    required int totalCents,
    String? customerName,
    DateTime? expiresAt,
    String? notes,
    TicketConfig config = const TicketConfig(),
  }) async {
    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy');

    pw.Widget row(String a, String b, {bool bold = false}) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(a,
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ),
            pw.Text(b,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
              child: pw.Text(config.title,
                  style:
                      pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold))),
          if (config.subheading.isNotEmpty)
            pw.Center(
                child: pw.Text(config.subheading,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9))),
          pw.Center(
              child: pw.Text('COTIZACIÓN',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Text('Folio: $folio', style: const pw.TextStyle(fontSize: 9)),
          if (customerName != null)
            pw.Text('Cliente: $customerName',
                style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Fecha: ${df.format(dateTime)}',
              style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          for (final l in lines)
            row('${l.qty} x ${l.description}  (${_m(l.unitPriceCents)})',
                _m(l.lineTotalCents)),
          pw.Divider(),
          row('TOTAL', _m(totalCents), bold: true),
          pw.SizedBox(height: 4),
          if (expiresAt != null)
            pw.Text('Vigencia: hasta ${df.format(expiresAt)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          if (notes != null && notes.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Nota: $notes', style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 8),
          pw.Center(
              child: pw.Text('Precios sujetos a cambio sin previo aviso',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8))),
          if (config.qrData.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: config.qrData,
                width: 90,
                height: 90,
                drawText: false,
              ),
            ),
          ],
        ],
      ),
    ));
    return doc.save();
  }
}
