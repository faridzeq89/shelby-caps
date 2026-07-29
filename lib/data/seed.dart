import 'local/database.dart';

/// Siembra SOLO la base operativa mínima: la sucursal `Principal` y el prefijo
/// de folios del dispositivo. **El catálogo NO se siembra**: la tienda arranca
/// con catálogo vacío y el dueño carga su mercancía real (Catálogo → Importar,
/// o alta manual). Antes se cargaban ~12 productos de ejemplo; se quitó.
class SeedService {
  SeedService(this._db);
  final AppDatabase _db;

  static const defaultDevicePrefix = 'T1';

  Future<int> run() async {
    final locationId = await _ensureLocation();
    await _ensureDevicePrefix();
    return locationId;
  }

  Future<int> _ensureLocation() async {
    final existing = await _db.select(_db.locations).get();
    if (existing.isNotEmpty) return existing.first.id;
    return _db.into(_db.locations).insert(
          LocationsCompanion.insert(name: 'Principal'),
        );
  }

  Future<void> _ensureDevicePrefix() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals('device_prefix')))
        .getSingleOrNull();
    if (row == null) {
      await _db.into(_db.appSettings).insert(
            AppSettingsCompanion.insert(
              key: 'device_prefix',
              value: defaultDevicePrefix,
            ),
          );
    }
  }
}
