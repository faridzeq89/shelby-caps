import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Base local en archivo: la fuente de verdad de la tablet.
/// El archivo es el mismo que sube y baja el respaldo en la nube.
QueryExecutor openDatabase() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'boutique_pos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// En esta plataforma el respaldo a Supabase sí está disponible.
const bool supportsFileBackup = true;

/// Foto consistente de la base vía `VACUUM INTO` (no copia un archivo a medio
/// escribir). Devuelve los bytes que se suben a la nube.
Future<Uint8List> snapshotDatabase(
    Future<void> Function(String sql) exec) async {
  final dir = await getApplicationDocumentsDirectory();
  final tmp = File(p.join(dir.path, 'backup_tmp.sqlite'));
  if (await tmp.exists()) await tmp.delete();
  // SQLite acepta '/' incluso en Windows.
  final path = tmp.path.replaceAll(r'\', '/');
  await exec("VACUUM INTO '$path'");
  final bytes = await tmp.readAsBytes();
  await tmp.delete();
  return bytes;
}

/// Reemplaza el archivo de la base con lo bajado de la nube. El llamador cierra
/// la base antes y avisa que hay que reiniciar la app.
Future<void> replaceDatabaseFile(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'boutique_pos.sqlite'));
  await file.writeAsBytes(bytes, flush: true);
}
