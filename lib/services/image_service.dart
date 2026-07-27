import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Guarda y optimiza las fotos de producto en almacenamiento local. Local-first:
/// la imagen vive en la tablet (se va en el respaldo del archivo de la base) y
/// en la tabla solo guardamos su ruta.
///
/// Optimización: se redimensiona el lado mayor a [_maxSide] px y se recodifica a
/// JPEG de calidad [_quality]. Una foto de cámara de varios MB queda en ~30-60 KB,
/// suficiente para el mostrador y ligera para el respaldo y el scroll.
class ImageService {
  static const _dirName = 'product_images';
  static const _maxSide = 1000; // px del lado mayor
  static const _quality = 82;

  static const _uuid = Uuid();

  Future<Directory> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Optimiza los [bytes] de una imagen y la guarda. Devuelve la ruta absoluta
  /// del archivo guardado, lista para persistir en `products.image_path`.
  /// Devuelve `null` si los bytes no son una imagen válida.
  Future<String?> saveOptimizedBytes(Uint8List bytes) async {
    final optimized = optimize(bytes);
    if (optimized == null) return null;
    final dir = await _imagesDir();
    final file = File(p.join(dir.path, '${_uuid.v4()}.jpg'));
    await file.writeAsBytes(optimized, flush: true);
    return file.path;
  }

  /// Redimensiona y recomprime en memoria. Aislado del disco para poder
  /// probarlo. Devuelve JPEG optimizado, o `null` si no decodifica.
  static Uint8List? optimize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest =
        decoded.width >= decoded.height ? decoded.width : decoded.height;
    final resized = longest > _maxSide
        ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: _maxSide)
            : img.copyResize(decoded, height: _maxSide))
        : decoded;
    return img.encodeJpg(resized, quality: _quality);
  }

  /// Borra el archivo de imagen si es local (no toca los assets del demo).
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    if (isAsset(path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // No es crítico: una imagen huérfana no rompe nada.
    }
  }

  static bool isAsset(String path) => path.startsWith('assets/');
}

/// Proveedor de imagen para pintar una foto de producto, sea un asset del demo
/// (`assets/...`) o un archivo local capturado por el usuario. `null` si no hay
/// ruta o el archivo ya no existe.
ImageProvider? productImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (ImageService.isAsset(path)) return AssetImage(path);
  final file = File(path);
  if (!file.existsSync()) return null;
  return FileImage(file);
}
