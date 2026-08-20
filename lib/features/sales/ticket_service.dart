import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/local/database.dart';

class TicketLine {
  const TicketLine({
    required this.description,
    required this.qty,
    required this.unitPriceCents,
    required this.lineTotalCents,
  });
  final String description;
  final int qty;
  final int unitPriceCents;
  final int lineTotalCents;
}

/// Personalización del ticket (marca), editable en Admin → Impresoras & Tickets.
/// Se guarda en `app_settings`. Todo es opcional salvo el título; los campos
/// vacíos simplemente no se imprimen.
class TicketConfig {
  const TicketConfig({
    this.title = 'SHELBY CAPS',
    this.subheading = '',
    this.footerLegend = '¡Gracias por su compra!',
    this.qrData = '',
  });

  final String title; // encabezado (nombre del negocio)
  final String subheading; // bajo el título: dirección, teléfono, eslogan…
  final String footerLegend; // leyenda al pie
  final String qrData; // contenido del QR (URL/texto); vacío = sin QR

  static const kTitle = 'ticket_title';
  static const kSubheading = 'ticket_subheading';
  static const kFooter = 'ticket_footer';
  static const kQr = 'ticket_qr';

  /// Lee la configuración desde `app_settings`. Si una clave no existe usa el
  /// valor por defecto (retrocompatibilidad con instalaciones previas).
  static Future<TicketConfig> load(AppDatabase db) async {
    Future<String?> get(String key) async {
      final row = await (db.select(db.appSettings)
            ..where((t) => t.key.equals(key)))
          .getSingleOrNull();
      return row?.value;
    }

    const def = TicketConfig();
    final title = (await get(kTitle))?.trim();
    return TicketConfig(
      title: (title != null && title.isNotEmpty) ? title : def.title,
      subheading: (await get(kSubheading))?.trim() ?? def.subheading,
      footerLegend: (await get(kFooter)) ?? def.footerLegend,
      qrData: (await get(kQr))?.trim() ?? def.qrData,
    );
  }
}

class TicketData {
  const TicketData({
    required this.folio,
    required this.dateTime,
    required this.cashierName,
    required this.lines,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.payments,
    required this.changeCents,
    required this.gift,
  });

  final String folio;
  final DateTime dateTime;
  final String cashierName;
  final List<TicketLine> lines;
  final int subtotalCents; // bruto (IVA incluido)
  final int discountCents;
  final int taxCents; // IVA incluido, informativo
  final int totalCents; // neto
  final List<(String, int)> payments; // (etiqueta, monto)
  final int changeCents;
  final bool gift;
}

/// Genera el ticket como PDF en formato rollo (80mm). El envío a impresora
/// térmica ESC/POS se conecta cuando se defina el modelo (Fase 0 #6); mientras,
/// este PDF se imprime/comparte desde el diálogo del sistema.
class TicketService {
  const TicketService._();

  static String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

  static Future<Uint8List> buildPdf(
    TicketData t, {
    TicketConfig config = const TicketConfig(),
  }) async {
    final doc = pw.Document();
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

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

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(config.title,
                  style:
                      pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ),
            if (config.subheading.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(config.subheading,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
            pw.SizedBox(height: 4),
            pw.Text('Folio: ${t.folio}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(fmt.format(t.dateTime),
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Atendió: ${t.cashierName}',
                style: const pw.TextStyle(fontSize: 9)),
            if (t.gift)
              pw.Center(
                child: pw.Text('*** TICKET DE REGALO ***',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
            pw.Divider(),
            for (final l in t.lines)
              t.gift
                  ? pw.Text('${l.qty} x ${l.description}',
                      style: const pw.TextStyle(fontSize: 9))
                  : pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Text(l.description,
                            style: const pw.TextStyle(fontSize: 9)),
                        row('  ${l.qty} x ${_money(l.unitPriceCents)}',
                            _money(l.lineTotalCents)),
                      ],
                    ),
            pw.Divider(),
            if (!t.gift) ...[
              if (t.discountCents > 0)
                row('Descuento', '-${_money(t.discountCents)}'),
              row('TOTAL', _money(t.totalCents), bold: true),
              // Sin IVA no se imprime el renglón: el negocio no factura y un
              // impuesto en el ticket confunde al cliente.
              if (t.taxCents > 0) row('IVA incluido', _money(t.taxCents)),
              pw.SizedBox(height: 4),
              // Solo el nombre del método de pago: el monto ya se ve en TOTAL
              // (y si se repite en cada método, confunde en vez de aclarar).
              for (final p in t.payments)
                pw.Text(p.$1, style: const pw.TextStyle(fontSize: 9)),
              if (t.changeCents > 0) row('Cambio', _money(t.changeCents)),
            ],
            if (config.footerLegend.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(config.footerLegend,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ),
            ],
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
      ),
    );
    return doc.save();
  }
}
