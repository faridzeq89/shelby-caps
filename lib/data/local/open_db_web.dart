import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Base local en el navegador: SQLite compilado a **WASM**, guardado por Drift
/// en el almacenamiento del navegador (OPFS o IndexedDB, lo que soporte).
///
/// Necesita dos archivos servidos junto a la app, en `web/`:
///   - `sqlite3.wasm`      (el motor)
///   - `drift_worker.js`   (el worker que lo corre fuera del hilo de UI)
///
/// Advertencia operativa: **los datos viven en ese navegador y en ese equipo**.
/// Borrar los datos del sitio los borra. Por eso esta versión es provisional
/// (mientras sale la licencia de iOS) y el respaldo en la nube se deshabilita:
/// aquí no hay archivo que subir.
QueryExecutor openDatabase() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'boutique_pos',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}

/// El respaldo a Supabase (que sube el archivo .sqlite) no aplica en web:
/// la base vive dentro del navegador y no hay archivo que subir.
const bool supportsFileBackup = false;

Future<Uint8List> snapshotDatabase(
    Future<void> Function(String sql) exec) async {
  throw UnsupportedError('El respaldo por archivo no aplica en el navegador');
}

Future<void> replaceDatabaseFile(Uint8List bytes) async {
  throw UnsupportedError('El respaldo por archivo no aplica en el navegador');
}
