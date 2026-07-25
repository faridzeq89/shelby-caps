import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Operaciones de catálogo que cruzan la frontera de permisos.
class CatalogRepository {
  CatalogRepository(this._db);
  final AppDatabase _db;

  /// Cambia el precio de una variante. Solo admin/gerente; queda registrado en
  /// `audit_log`. Un cajero recibe [PermissionException].
  Future<void> updateVariantPrice({
    required Profile actor,
    required int variantId,
    required int newPriceCents,
  }) async {
    if (!Permissions.canEditPrices(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede editar precios');
    }
    await _db.transaction(() async {
      await (_db.update(_db.variants)..where((t) => t.id.equals(variantId)))
          .write(VariantsCompanion(priceCentsOverride: Value(newPriceCents)));
      await _db.into(_db.auditLog).insert(
            AuditLogCompanion.insert(
              userId: Value(actor.id),
              action: 'update_price',
              entityType: 'variant',
              entityId: Value(variantId.toString()),
              detail: Value('priceCents=$newPriceCents'),
            ),
          );
    });
  }
}
