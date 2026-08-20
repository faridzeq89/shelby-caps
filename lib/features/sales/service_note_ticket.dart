import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/local/database.dart';
import 'ticket_service.dart';

String serviceItemTypeLabel(ServiceItemType t) => switch (t) {
      ServiceItemType.tenis => 'Tenis',
      ServiceItemType.gorra => 'Gorra',
      ServiceItemType.bolsa => 'Bolsa',
    };

/// Nota de servicio (formato rollo 80mm, como el ticket): lo que se recibió,
/// para reclamar la pieza — sin precio, eso se cobra aparte con venta directa.
class ServiceNoteTicket {
  const ServiceNoteTicket._();

  static Future<Uint8List> build(
    ServiceNote note, {
    TicketConfig config = const TicketConfig(),
  }) async {
    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm');

    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              pw.Text('$label: ',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Expanded(
                  child: pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
            ],
          ),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
              child: pw.Text(config.title,
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold))),
          if (config.subheading.isNotEmpty)
            pw.Center(
                child: pw.Text(config.subheading,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9))),
          pw.Center(
              child: pw.Text('NOTA DE SERVICIO',
                  style:
                      pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Text('Folio: ${note.folio}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(df.format(note.createdAt),
              style: const pw.TextStyle(fontSize: 9)),
          pw.Divider(),
          row('Cliente', note.customerName),
          row('Tipo', serviceItemTypeLabel(note.itemType)),
          if (note.brand != null && note.brand!.isNotEmpty)
            row('Marca', note.brand!),
          if (note.color != null && note.color!.isNotEmpty)
            row('Color', note.color!),
          pw.Divider(),
          pw.Center(
              child: pw.Text('Conserva esta nota para recoger tu pieza',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold))),
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
