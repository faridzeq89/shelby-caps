import 'dart:js_interop';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// Base local en el navegador: SQLite compilado a **WASM**.
///
/// Necesita dos archivos servidos junto a la app, en `web/`:
///   - `sqlite3.wasm`      (el motor)
///   - `drift_worker.js`   (el worker que lo corre fuera del hilo de UI)
///
/// ## Por qué importa dónde guarda
///
/// El navegador ofrece dos almacenamientos y **no son igual de seguros**:
///
/// - **OPFS** (sistema de archivos privado): escritura síncrona y durable. Es
///   el bueno, pero solo está disponible si la página se sirve **aislada**
///   (cabeceras COOP/COEP, ver `web/_headers`). Sin eso, Chrome no lo permite.
/// - **IndexedDB**: el `sqlite3` que usa drift lo documenta así — *"writes are
///   asynchronously written to IndexedDB **without any durability
///   guarantees**"*. La base vive en memoria y se vuelca después. Si el dueño
///   cambia un precio y cierra la pestaña, el volcado puede no alcanzar a
///   ocurrir: **el cambio se pierde**. Esto fue un bug real reportado por el
///   cliente el 13 ago 2026, no una precaución teórica.
///
/// Por eso aquí se pide OPFS, se **migra** lo que ya estaba en IndexedDB
/// ([moveExistingIndexedDbToOpfs]) y, si aun así toca IndexedDB, la app lo
/// dice en vez de fingir que guardó (ver [storageIsDurable]).
///
/// Advertencia operativa: **los datos viven en ese navegador y en ese equipo**.
/// Borrar los datos del sitio los borra. Por eso esta versión es provisional
/// (mientras sale la licencia de iOS) y el respaldo en la nube se deshabilita:
/// aquí no hay archivo que subir.
QueryExecutor openDatabase() {
  return LazyDatabase(() async {
    // Sin esto el navegador puede **desalojar** los datos del sitio cuando le
    // falte espacio, sin avisar. Con esto quedan marcados como "no los borres".
    await _requestPersistentStorage();

    final result = await WasmDatabase.open(
      databaseName: 'boutique_pos',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      // Drift, por omisión, se queda en IndexedDB si ya había una base ahí,
      // aunque OPFS esté disponible. Es justo el caso del cliente: hay que
      // mudarlo, no dejarlo en el almacenamiento que pierde escrituras. Si la
      // mudanza falla, drift sigue con la base vieja (no se pierde nada).
      moveExistingIndexedDbToOpfs: true,
    );

    storageKind = result.chosenImplementation.name;
    storageIsDurable =
        result.chosenImplementation.storageApi == WebStorageApi.opfs;
    storageMissingFeatures =
        result.missingFeatures.map((f) => f.name).toList(growable: false);

    return result.resolvedExecutor;
  });
}

/// Cómo terminó guardando el navegador (`opfsLocks`, `unsafeIndexedDb`, …).
/// Vacío hasta que la base se abre de verdad.
String storageKind = '';

/// `true` solo si el almacenamiento **no pierde escrituras** al cerrar. Cuando
/// es `false` la app tiene que decirlo: es la diferencia entre "guardé" y
/// "creo que guardé".
bool storageIsDurable = false;

/// Qué le faltó al navegador para poder usar el almacenamiento bueno. Sirve
/// para diagnosticar sin adivinar (típico: falta el aislamiento COOP/COEP).
List<String> storageMissingFeatures = const [];

/// Le pide al navegador que **no** desaloje los datos de este sitio.
/// Silencioso a propósito: si no se puede, la app igual abre.
Future<void> _requestPersistentStorage() async {
  try {
    final storage = _navigator.storage;
    if (storage == null) return;
    if (await storage.persisted().toDart.then((v) => v.toDart)) return;
    await storage.persist().toDart;
  } catch (_) {
    // Navegador sin la API (o en modo privado): seguimos igual.
  }
}

@JS('navigator')
external _Navigator get _navigator;

extension type _Navigator._(JSObject _) implements JSObject {
  external _StorageManager? get storage;
}

extension type _StorageManager._(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> persist();
  external JSPromise<JSBoolean> persisted();
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

/// Borra por completo la base local del navegador (**empezar de cero**) y
/// recarga la página para que la app se vuelva a sembrar limpia. Usa la API de
/// drift (`probe`/`deleteDatabase`), que cubre tanto OPFS como IndexedDB — más
/// seguro que borrar filas (el libro mayor `inventory_movements` tiene triggers
/// que impiden borrarlo) o tocar el almacenamiento a mano. El llamador cierra la
/// base antes. Recarga siempre, aunque el borrado falle, para no dejar la app a
/// medias.
Future<void> wipeLocalDatabaseAndReload() async {
  try {
    final probe = await WasmDatabase.probe(
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
      databaseName: 'boutique_pos',
    );
    for (final existing in probe.existingDatabases) {
      // existing = (WebStorageApi, String nombre): solo la nuestra.
      if (existing.$2 == 'boutique_pos') {
        await probe.deleteDatabase(existing);
      }
    }
  } finally {
    reloadApp();
  }
}

/// Exporta la base local del navegador como los bytes de un archivo SQLite, para
/// subirla a la nube y que la **app nativa la restaure** (paso a iOS sin perder
/// datos). Usa la API de drift (`probe`/`exportDatabase`), que lee la base sin
/// borrarla. **El llamador cierra la base antes** para soltar el candado de OPFS
/// (con la base abierta, OPFS no deja que otro proceso la lea).
Future<Uint8List> exportDatabaseBytes() async {
  final probe = await WasmDatabase.probe(
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
    databaseName: 'boutique_pos',
  );
  for (final existing in probe.existingDatabases) {
    if (existing.$2 == 'boutique_pos') {
      final bytes = await probe.exportDatabase(existing);
      if (bytes != null) return bytes;
    }
  }
  throw StateError('No se encontró la base local para exportar.');
}

/// Recarga la página (en web reabre la app y su base). En nativo no aplica.
void reloadApp() => _jsLocation.reload();

@JS('location')
external _Location get _jsLocation;

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}
