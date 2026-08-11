import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import 'image_store.dart';

/// Guarda y optimiza las fotos de producto. Local-first: la imagen vive en el
/// dispositivo (se va en el respaldo del archivo de la base) y en la tabla solo
/// guardamos una referencia.
///
/// Optimización: se redimensiona el lado mayor a [_maxSide] px y se recodifica a
/// JPEG de calidad [_quality]. Una foto de cámara de varios MB queda en ~30-60 KB,
/// suficiente para el mostrador y ligera para el respaldo y el scroll.
///
/// Dónde queda guardada depende de la plataforma (ver `image_store.dart`):
/// archivo en tablet/PC, data URL en el navegador.
class ImageService {
  static const _maxSide = 1000; // px del lado mayor
  static const _quality = 82;

  /// Optimiza los [bytes] de una imagen y la guarda. Devuelve la referencia
  /// lista para persistir en `products.image_path`, o `null` si los bytes no
  /// son una imagen válida.
  Future<String?> saveOptimizedBytes(Uint8List bytes) async {
    final optimized = optimize(bytes);
    if (optimized == null) return null;
    return persistImage(optimized);
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

  /// Borra la imagen si es local (no toca los assets del demo).
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty) return;
    if (isAsset(path)) return;
    await deleteImage(path);
  }

  /// Bytes de la imagen, para subirla al publicar el catálogo.
  static Future<Uint8List?> bytesOf(String path) => readImageBytes(path);

  static bool isAsset(String path) => path.startsWith('assets/');
}

/// Proveedor de imagen para pintar una foto de producto, sea un asset del demo
/// (`assets/...`), un archivo local o una data URL (web). `null` si no hay
/// referencia o la imagen ya no está.
ImageProvider? productImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (ImageService.isAsset(path)) return AssetImage(path);
  return imageProviderFor(path);
}
