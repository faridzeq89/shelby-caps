import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

const _prefix = 'data:image/jpeg;base64,';

/// En el navegador la foto se guarda como data URL en la propia columna.
/// Ya viene optimizada (~30-60 KB), así que en base64 son ~40-80 KB por foto:
/// aceptable para la versión provisional en Chrome.
Future<String> persistImage(Uint8List optimized) async {
  return _prefix + base64Encode(optimized);
}

/// No hay archivo suelto que borrar: la foto se va con la fila.
Future<void> deleteImage(String path) async {}

Future<Uint8List?> readImageBytes(String path) async {
  if (!path.startsWith('data:')) return null;
  final comma = path.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(path.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// `null` si [path] no es ni data URL ni una URL ya publicada.
///
/// Una vez que algo se publica (p. ej. la tarjeta digital), su data URL local
/// se reemplaza por la URL pública de Supabase — hay que pintarla por red.
ImageProvider? imageProviderFor(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }
  if (!path.startsWith('data:')) return null;
  final comma = path.indexOf(',');
  if (comma < 0) return null;
  try {
    return MemoryImage(base64Decode(path.substring(comma + 1)));
  } catch (_) {
    return null;
  }
}
