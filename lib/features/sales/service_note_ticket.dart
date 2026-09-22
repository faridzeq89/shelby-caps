import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/ui_kit.dart' show money;
import '../../data/local/database.dart';
import '../../data/repositories/service_note_repository.dart';
import 'ticket_service.dart';

String serviceItemTypeLabel(ServiceItemType t) => switch (t) {
      ServiceItemType.tenis => 'Tenis',
      ServiceItemType.gorra => 'Gorra',
      ServiceItemType.bolsa => 'Bolsos',
    };

/// Resumen corto de las piezas para la lista y la descripción del cobro:
/// "2 Tenis, 1 Gorra".
String serviceItemsSummary(List<ServiceItem> items) => items
    .map((i) =>
        '${i.qty > 1 ? '${i.qty} ' : ''}${serviceItemTypeLabel(i.itemType)}')
    .join(', ');

/// Nota de servicio en papel (rollo 80mm), con la forma que pidió el cliente el
/// 20 ago 2026 y en ese orden:
///
///   Datos del negocio      — WhatsApp y ubicación, **de fábrica**, no se capturan
///   Datos del cliente      — nombre y WhatsApp
///   Información del artículo — marca, talla, color, artículo y cantidad
///   Costo del servicio
///   Notas adicionales
///
/// El costo impreso es lo **cotizado**, no un cobro: la nota es el papel que se
/// lleva el cliente para reclamar su pieza. El cobro se hace después, desde
/// Notas de servicio, y ahí se confirma el precio y sale su propio ticket.
class ServiceNoteTicket {
  const ServiceNoteTicket._();

  static Future<Uint8List> build(
    ServiceNote note, {
    TicketConfig config = const TicketConfig(),
  }) async {
    final doc = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final logo = await TicketBrand.logoOrTitle(config);
    final items = serviceNoteItems(note);

    pw.Widget titulo(String texto) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
          child: pw.Text(texto.toUpperCase(),
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('$label: ',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Expanded(
                  child:
                      pw.Text(value, style: const pw.TextStyle(fontSize: 9))),
            ],
          ),
        );

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(8),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          logo,
          pw.SizedBox(height: 2),
          pw.Center(
              child: pw.Text('NOTA DE SERVICIO',
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Text('Folio: ${note.folio}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(df.format(note.createdAt),
              style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Atendió: ${config.attendedBy}',
              style: const pw.TextStyle(fontSize: 9)),

          // Datos del negocio: no se capturan por nota, vienen de Ajustes →
          // Impresoras y tickets (con los del cliente de fábrica).
          if (config.businessPhone.isNotEmpty ||
              config.businessAddress.isNotEmpty) ...[
            titulo('Datos del negocio'),
            if (config.businessPhone.isNotEmpty)
              row('WhatsApp', config.businessPhone),
            if (config.businessAddress.isNotEmpty)
              row('Ubicación', config.businessAddress),
          ],

          titulo('Datos del cliente'),
          row('Nombre', note.customerName),
          if (note.customerPhone != null && note.customerPhone!.isNotEmpty)
            row('WhatsApp', note.customerPhone!),

          titulo(items.length > 1
              ? 'Piezas recibidas (${items.length})'
              : 'Información del artículo'),
          for (var i = 0; i < items.length; i++) ...[
            if (items.length > 1)
              pw.Text('Pieza ${i + 1}',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
            row(
                'Artículo',
                '${items[i].qty > 1 ? '${items[i].qty} × ' : ''}'
                    '${serviceItemTypeLabel(items[i].itemType)}'),
            if (items[i].brand != null && items[i].brand!.isNotEmpty)
              row('Marca', items[i].brand!),
            if (items[i].size != null && items[i].size!.isNotEmpty)
              row('Talla', items[i].size!),
            if (items[i].color != null && items[i].color!.isNotEmpty)
              row('Color', items[i].color!),
            if (i < items.length - 1) pw.SizedBox(height: 3),
          ],

          pw.Divider(),
          // Sin precio se imprime "Por definir" en vez de esconder el renglón:
          // que quede claro que falta acordarlo y no parezca gratis.
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Costo del servicio',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  note.priceCents == null
                      ? 'Por definir'
                      : money(note.priceCents!),
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),

          if (note.notes != null && note.notes!.isNotEmpty) ...[
            titulo('Notas adicionales'),
            pw.Text(note.notes!, style: const pw.TextStyle(fontSize: 9)),
          ],

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
