import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Directorio de proveedores: alta, edición, archivar y listado. Las acciones
/// exigen rol de catálogo ([Permissions.canManageCatalog]).
class SupplierRepository {
  SupplierRepository(this._db);
  final AppDatabase _db;

  void _require(Profile actor) {
    if (!Permissions.canManageCatalog(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede administrar proveedores');
    }
  }

  Future<int> create({
    required Profile actor,
    required String name,
    String? phone,
    String? contact,
    String? notes,
  }) async {
    _require(actor);
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('El nombre es obligatorio');
    return _db.into(_db.suppliers).insert(
          SuppliersCompanion.insert(
            name: n,
            phone: Value(_clean(phone)),
            contact: Value(_clean(contact)),
            notes: Value(_clean(notes)),
          ),
        );
  }

  Future<void> update({
    required Profile actor,
    required int id,
    required String name,
    String? phone,
    String? contact,
    String? notes,
  }) async {
    _require(actor);
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('El nombre es obligatorio');
    await (_db.update(_db.suppliers)..where((t) => t.id.equals(id))).write(
      SuppliersCompanion(
        name: Value(n),
        phone: Value(_clean(phone)),
        contact: Value(_clean(contact)),
        notes: Value(_clean(notes)),
      ),
    );
  }

  Future<void> setActive(Profile actor, int id, bool active) async {
    _require(actor);
    await (_db.update(_db.suppliers)..where((t) => t.id.equals(id)))
        .write(SuppliersCompanion(active: Value(active)));
  }

  Future<List<Supplier>> all({bool activeOnly = true}) {
    final q = _db.select(_db.suppliers)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (activeOnly) q.where((t) => t.active.equals(true));
    return q.get();
  }

  Future<Supplier?> byId(int id) =>
      (_db.select(_db.suppliers)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  String? _clean(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}
