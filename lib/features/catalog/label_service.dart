import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Datos mínimos para imprimir una etiqueta.
class LabelData {
  const LabelData({
    required this.productName,
    required this.code,
    required this.priceCents,
    this.size,
    this.color,
  });

  final String productName;
  final String code;
  final int priceCents;
  final String? size;
  final String? color;

  String get variantLine => [size, color].whereType<String>().join(' ').trim();
  String get priceLabel => '\$${(priceCents / 100).toStringAsFixed(2)}';
}

/// Genera etiquetas por las dos rutas de la Fase 0: PDF de hojas adhesivas y
/// ZPL para etiquetadora Zebra/Brother.
class LabelService {
  const LabelService._();

  /// Hoja de etiquetas en PDF (rejilla) con código de barras Code128.
  static Future<Uint8List> buildSheetPdf(List<LabelData> labels) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(18),
        build: (context) => [
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels.map(_pdfLabel).toList(),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _pdfLabel(LabelData l) {
    return pw.Container(
      width: 165,
      height: 95,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            l.productName,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          if (l.variantLine.isNotEmpty)
            pw.Text(l.variantLine, style: const pw.TextStyle(fontSize: 8)),
          pw.SizedBox(height: 3),
          pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: l.code,
            drawText: false,
            height: 28,
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(l.code, style: const pw.TextStyle(fontSize: 7)),
              pw.Text(l.priceLabel,
                  style:
                      pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  /// Texto ZPL para etiquetadora (Zebra habla ZPL, no ESC/POS). El envío al
  /// equipo depende del hardware; aquí se genera el contenido.
  static String buildZpl(List<LabelData> labels) {
    String esc(String s) => s.replaceAll('^', ' ').replaceAll('~', ' ');
    final b = StringBuffer();
    for (final l in labels) {
      b.writeln('^XA');
      b.writeln('^FO30,20^A0N,28,28^FD${esc(l.productName)}^FS');
      if (l.variantLine.isNotEmpty) {
        b.writeln('^FO30,55^A0N,24,24^FD${esc(l.variantLine)}^FS');
      }
      b.writeln('^FO30,90^BCN,70,Y,N,N^FD${l.code}^FS');
      b.writeln('^FO30,185^A0N,30,30^FD${esc(l.priceLabel)}^FS');
      b.writeln('^XZ');
    }
    return b.toString();
  }
}
