import 'package:drift/drift.dart';

import '../local/database.dart';

/// Única puerta al stock: registra movimientos en el ledger. Solo inserta —
/// nunca actualiza ni borra (y los triggers de la base lo garantizan además).
class InventoryRepository {
  InventoryRepository(this._db);
  final AppDatabase _db;

  Future<int> record({
    required int variantId,
    required int locationId,
    required int qty,
    required MovementType type,
    int? userId,
    String? reason,
    String? referenceType,
    String? referenceId,
  }) {
    return _db.into(_db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
            variantId: variantId,
            locationId: locationId,
            qty: qty,
            type: type,
            userId: Value(userId),
            reason: Value(reason),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
          ),
        );
  }

  Future<VariantStockData> stockFor(int variantId) => _db.stockFor(variantId);
}
