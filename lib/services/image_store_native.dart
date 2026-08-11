import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _dirName = 'product_images';
const _uuid = Uuid();

Future<Directory> _imagesDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, _dirName));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Guarda la foto ya optimizada y devuelve la ruta del archivo.
Future<String> persistImage(Uint8List optimized) async {
  final dir = await _imagesDir();
  final file = File(p.join(dir.path, '${_uuid.v4()}.jpg'));
  await file.writeAsBytes(optimized, flush: true);
  return file.path;
}

/// Borra el archivo. Una imagen huérfana no rompe nada, así que se ignoran fallos.
Future<void> deleteImage(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// Bytes de la foto, para subirla al publicar el catálogo.
Future<Uint8List?> readImageBytes(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Proveedor para pintarla. `null` si el archivo ya no existe.
ImageProvider? imageProviderFor(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
