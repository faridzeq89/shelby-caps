import 'dart:convert';
import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Utilidades para exportar reportes a CSV (se abre en Excel) y compartirlos
/// por la hoja de compartir del sistema, reutilizando `printing` (ya presente).
class ReportExport {
  const ReportExport._();

  /// Escapa un campo CSV (comillas, comas y saltos de línea).
  static String _cell(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  /// Construye un CSV a partir de encabezados y filas.
  static String toCsv(List<String> headers, List<List<Object?>> rows) {
    final buf = StringBuffer();
    buf.writeln(headers.map(_cell).join(','));
    for (final row in rows) {
      buf.writeln(row.map(_cell).join(','));
    }
    return buf.toString();
  }

  /// Convierte centavos a texto de pesos ("12345" -> "123.45").
  static String money(int cents) => (cents / 100).toStringAsFixed(2);

  /// Comparte el CSV como archivo (BOM UTF-8 para acentos en Excel).
  static Future<void> share(String csv, String filename) async {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}
