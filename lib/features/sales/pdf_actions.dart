import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../core/ui_kit.dart';

/// Qué hacer con un documento recién generado: **compartirlo** con el cliente o
/// imprimirlo.
///
/// Antes solo se abría el diálogo de impresión del sistema. Ahí compartir está
/// escondido detrás de "guardar como PDF" y luego buscar el archivo, así que en
/// la práctica no había forma de mandarle el ticket al cliente por WhatsApp.
///
/// [build] se llama una sola vez y su resultado se reusa para ambas acciones.
Future<void> showDocumentActions(
  BuildContext context, {
  required String title,
  required String filename,
  required Future<Uint8List> Function(PdfPageFormat format) build,
  String shareLabel = 'Compartir',
  String shareHint = 'Mandarlo por WhatsApp, correo o guardarlo',
}) async {
  Uint8List? bytes;
  Future<Uint8List> pdf() async =>
      bytes ??= await build(PdfPageFormat.roll80);

  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Text(title,
                style: Theme.of(sheetCtx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share, color: AppColors.brassDeep),
            title: Text(shareLabel,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(shareHint),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Printing.sharePdf(bytes: await pdf(), filename: filename);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo compartir: $e')));
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined,
                color: AppColors.brassDeep),
            title: const Text('Imprimir',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Impresora de tickets o PDF'),
            onTap: () async {
              Navigator.of(sheetCtx).pop();
              try {
                await Printing.layoutPdf(
                    onLayout: (format) => build(format), name: filename);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo imprimir: $e')));
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
