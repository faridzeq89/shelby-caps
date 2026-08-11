import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Anuncios de la tienda en línea: la portada y los banners que rotan.
///
/// Solo admin/gerente puede tocarlos: son la cara pública del negocio, no algo
/// que deba cambiar un cajero desde el mostrador.
class BannerRepository {
  BannerRepository(this._db);
  final AppDatabase _db;

  void _require(Profile actor) {
    if (!Permissions.canManageCatalog(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede cambiar los anuncios');
    }
  }

  /// Banners (sin la portada), en el orden en que se muestran.
  Future<List<StoreBanner>> banners() {
    return (_db.select(_db.storeBanners)
          ..where((t) => t.isCover.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();
  }

  /// Portada actual, o `null` si no hay. Si hubiera varias, gana la última.
  Future<StoreBanner?> cover() {
    return (_db.select(_db.storeBanners)
          ..where((t) => t.isCover.equals(true) & t.active.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Agrega un banner al final de la lista.
  Future<int> addBanner(
    Profile actor, {
    required String path,
    String? caption,
    String? link,
  }) async {
    _require(actor);
    final existing = await banners();
    final next = existing.isEmpty ? 0 : existing.last.position + 1;
    return _db.into(_db.storeBanners).insert(StoreBannersCompanion.insert(
          path: path,
          caption: Value(caption),
          link: Value(link),
          position: Value(next),
        ));
  }

  /// Fija la portada. Devuelve la ruta de la anterior para que quien llama
  /// borre el archivo; el repositorio no toca el sistema de archivos.
  Future<String?> setCover(Profile actor, {required String path}) async {
    _require(actor);
    final previous = await cover();
    await _db.transaction(() async {
      await (_db.delete(_db.storeBanners)..where((t) => t.isCover.equals(true))).go();
      await _db.into(_db.storeBanners).insert(StoreBannersCompanion.insert(
            path: path,
            isCover: const Value(true),
          ));
    });
    return previous?.path;
  }

  /// Quita un anuncio. Devuelve su ruta para borrar el archivo.
  Future<String?> remove(Profile actor, int id) async {
    _require(actor);
    final row = await (_db.select(_db.storeBanners)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    await (_db.delete(_db.storeBanners)..where((t) => t.id.equals(id))).go();
    return row.path;
  }

  /// Prende o apaga un banner sin borrarlo: sirve para guardar la promoción de
  /// temporada y volver a encenderla el año que viene.
  Future<void> setActive(Profile actor, int id, bool active) async {
    _require(actor);
    await (_db.update(_db.storeBanners)..where((t) => t.id.equals(id)))
        .write(StoreBannersCompanion(active: Value(active)));
  }

  /// Mueve un banner una posición arriba (`-1`) o abajo (`1`) intercambiándolo
  /// con su vecino.
  Future<void> move(Profile actor, int id, int delta) async {
    _require(actor);
    final list = await banners();
    final i = list.indexWhere((b) => b.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= list.length) return;
    await _db.transaction(() async {
      await (_db.update(_db.storeBanners)..where((t) => t.id.equals(list[i].id)))
          .write(StoreBannersCompanion(position: Value(list[j].position)));
      await (_db.update(_db.storeBanners)..where((t) => t.id.equals(list[j].id)))
          .write(StoreBannersCompanion(position: Value(list[i].position)));
    });
  }

  /// Lo que se publica a la tienda: portada primero, luego los banners activos.
  Future<List<StoreBanner>> published() async {
    final c = await cover();
    final list = await banners();
    return [
      ?c,
      ...list.where((b) => b.active),
    ];
  }
}
