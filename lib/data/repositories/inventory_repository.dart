import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Una línea de recepción de mercancía (una variante y su cantidad recibida).
class ReceiptLine {
  const ReceiptLine({
    required this.variantId,
    required this.qty,
    this.unitCostCents,
    this.updateCost = false,
  });
  final int variantId;
  final int qty;

  /// Costo unitario de esta entrada. Si [updateCost] es true, se guarda como el
  /// nuevo `cost_cents` de la variante (costeo por último costo).
  final int? unitCostCents;
  final bool updateCost;
}

/// Motivo de un ajuste manual de stock (fuera de venta/recepción/devolución).
enum AdjustmentReason { loss, damaged, theft, correction, other }

extension AdjustmentReasonLabel on AdjustmentReason {
  String get label => switch (this) {
        AdjustmentReason.loss => 'Merma',
        AdjustmentReason.damaged => 'Dañado',
        AdjustmentReason.theft => 'Robo',
        AdjustmentReason.correction => 'Corrección de captura',
        AdjustmentReason.other => 'Otro',
      };
}

/// Variante por debajo de su mínimo (alimenta la campana de stock bajo).
class LowStockItem {
  const LowStockItem({
    required this.product,
    required this.variant,
    required this.available,
    required this.threshold,
  });
  final Product product;
  final Variant variant;
  final int available;
  final int threshold;
}

/// Una línea de conteo físico con su diferencia contra el sistema.
class CountLineView {
  const CountLineView({
    required this.line,
    required this.product,
    required this.variant,
  });
  final StockCountLine line;
  final Product product;
  final Variant variant;

  /// >0 sobra físico (entra stock), <0 falta físico (sale stock).
  int get difference => line.countedQty - line.systemQty;
}

/// Única puerta al stock: registra movimientos en el ledger append-only. Solo
/// inserta movimientos — nunca actualiza ni borra (y los triggers de la base lo
/// garantizan además). El stock es siempre una consulta sobre el ledger.
///
/// Reglas de rol: recibir, ajustar, contar y fijar mínimos exige gerente/admin;
/// el cajero consulta pero no mueve inventario.
class InventoryRepository {
  InventoryRepository(this._db);
  final AppDatabase _db;

  static const _lowStockDefaultKey = 'low_stock_default';
  static const lowStockDefaultFallback = 3;

  void _requireInventory(Profile actor) {
    if (!Permissions.canManageInventory(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede mover el inventario');
    }
  }

  // ---------------------------------------------------------------------------
  // Lecturas de stock
  // ---------------------------------------------------------------------------

  /// Registro directo de un movimiento (uso interno/genérico). Prefiere los
  /// métodos con reglas de negocio (recepción, ajuste, conteo).
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

  /// La ubicación por defecto (single-tenant: una sola tienda). Los traspasos
  /// entre ubicaciones se activarán cuando exista una segunda sucursal.
  Future<int> defaultLocationId() async {
    final loc = await (_db.select(_db.locations)
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(1))
        .getSingleOrNull();
    if (loc == null) throw StateError('No hay ninguna ubicación configurada');
    return loc.id;
  }

  // ---------------------------------------------------------------------------
  // Recepción de mercancía (movimientos `receipt`, cantidad positiva)
  // ---------------------------------------------------------------------------
  Future<void> receiveBatch(
    Profile actor, {
    required int locationId,
    required List<ReceiptLine> lines,
    String? reason,
    String? referenceId,
  }) async {
    _requireInventory(actor);
    if (lines.isEmpty) throw ArgumentError('Nada por recibir');
    for (final l in lines) {
      if (l.qty <= 0) throw ArgumentError('La cantidad recibida debe ser > 0');
    }
    await _db.transaction(() async {
      for (final l in lines) {
        await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                variantId: l.variantId,
                locationId: locationId,
                qty: l.qty,
                type: MovementType.receipt,
                userId: Value(actor.id),
                reason: Value(reason ?? 'Recepción de mercancía'),
                referenceType: const Value('receipt'),
                referenceId: Value(referenceId),
              ),
            );
        if (l.updateCost && l.unitCostCents != null) {
          await (_db.update(_db.variants)
                ..where((t) => t.id.equals(l.variantId)))
              .write(VariantsCompanion(costCents: Value(l.unitCostCents!)));
          await _audit(actor, 'update_cost', 'variant', l.variantId.toString(),
              'costCents=${l.unitCostCents} (recepción)');
        }
      }
      final totalQty = lines.fold<int>(0, (s, l) => s + l.qty);
      await _audit(actor, 'receipt', 'inventory', referenceId,
          'lines=${lines.length}; qty=$totalQty; loc=$locationId');
    });
  }

  // ---------------------------------------------------------------------------
  // Ajuste manual (movimiento `adjustment`, con motivo obligatorio)
  // ---------------------------------------------------------------------------
  Future<int> adjust(
    Profile actor, {
    required int variantId,
    required int locationId,
    required int qty, // con signo, distinto de cero
    required AdjustmentReason reason,
    String? note,
    Profile? authorizedBy,
  }) async {
    if (!Permissions.canManageInventory(actor.role) && authorizedBy == null) {
      throw PermissionException(
          'El ajuste de stock requiere autorización de gerente');
    }
    if (qty == 0) throw ArgumentError('El ajuste no puede ser de cero piezas');
    final trimmed = note?.trim();
    final detail = (trimmed == null || trimmed.isEmpty)
        ? reason.label
        : '${reason.label}: $trimmed';
    return _db.transaction(() async {
      final id = await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
              variantId: variantId,
              locationId: locationId,
              qty: qty,
              type: MovementType.adjustment,
              userId: Value((authorizedBy ?? actor).id),
              reason: Value(detail),
              referenceType: const Value('adjustment'),
            ),
          );
      await _audit(actor, 'adjustment', 'variant', variantId.toString(),
          'qty=$qty; $detail${authorizedBy != null ? '; auth=${authorizedBy.id}' : ''}');
      return id;
    });
  }

  // ---------------------------------------------------------------------------
  // Conteo físico (sesión sobre stock_counts / stock_count_lines)
  // ---------------------------------------------------------------------------

  /// Conteo abierto (solo puede haber uno a la vez para evitar confusión).
  Future<StockCount?> openCount() => (_db.select(_db.stockCounts)
        ..where((t) => t.status.equalsValue(StockCountStatus.open))
        ..limit(1))
      .getSingleOrNull();

  Future<int> createCount(Profile actor, {int? locationId}) async {
    _requireInventory(actor);
    final existing = await openCount();
    if (existing != null) return existing.id;
    return _db.into(_db.stockCounts).insert(StockCountsCompanion.insert(
          locationId: locationId ?? await defaultLocationId(),
          status: StockCountStatus.open,
          createdBy: actor.id,
        ));
  }

  /// Captura (o corrige) el conteo de una variante. El `systemQty` se fija con
  /// el on_hand del momento de la captura, para el reporte de diferencias.
  Future<void> setCountLine(int countId, int variantId, int countedQty) async {
    if (countedQty < 0) throw ArgumentError('La cantidad contada no puede ser negativa');
    final onHand = (await _db.stockFor(variantId)).onHand;
    final existing = await (_db.select(_db.stockCountLines)
          ..where((t) => t.countId.equals(countId) & t.variantId.equals(variantId)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.stockCountLines).insert(StockCountLinesCompanion.insert(
            countId: countId,
            variantId: variantId,
            countedQty: countedQty,
            systemQty: onHand,
          ));
    } else {
      await (_db.update(_db.stockCountLines)..where((t) => t.id.equals(existing.id)))
          .write(StockCountLinesCompanion(
              countedQty: Value(countedQty), systemQty: Value(onHand)));
    }
  }

  Future<void> removeCountLine(int lineId) =>
      (_db.delete(_db.stockCountLines)..where((t) => t.id.equals(lineId))).go();

  Future<List<CountLineView>> countLines(int countId) async {
    final lines = await (_db.select(_db.stockCountLines)
          ..where((t) => t.countId.equals(countId))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    final out = <CountLineView>[];
    for (final l in lines) {
      final v = await (_db.select(_db.variants)..where((t) => t.id.equals(l.variantId)))
          .getSingle();
      final p = await (_db.select(_db.products)..where((t) => t.id.equals(v.productId)))
          .getSingle();
      out.add(CountLineView(line: l, product: p, variant: v));
    }
    return out;
  }

  /// Aplica el conteo: por cada línea con diferencia, inserta un movimiento
  /// `count` que lleva el on_hand al valor contado. Cierra la sesión. El delta
  /// se calcula contra el `systemQty` capturado (determinista y auditable).
  Future<int> applyCount(Profile actor, int countId) async {
    _requireInventory(actor);
    return _db.transaction(() async {
      final count = await (_db.select(_db.stockCounts)
            ..where((t) => t.id.equals(countId)))
          .getSingle();
      if (count.status != StockCountStatus.open) {
        throw StateError('El conteo ya no está abierto');
      }
      final lines = await (_db.select(_db.stockCountLines)
            ..where((t) => t.countId.equals(countId)))
          .get();
      var adjusted = 0;
      for (final l in lines) {
        final delta = l.countedQty - l.systemQty;
        if (delta == 0) continue;
        await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                variantId: l.variantId,
                locationId: count.locationId,
                qty: delta,
                type: MovementType.count,
                userId: Value(actor.id),
                reason: Value('Conteo físico #$countId'),
                referenceType: const Value('count'),
                referenceId: Value(countId.toString()),
              ),
            );
        adjusted++;
      }
      await (_db.update(_db.stockCounts)..where((t) => t.id.equals(countId)))
          .write(StockCountsCompanion(
              status: const Value(StockCountStatus.applied),
              appliedAt: Value(DateTime.now())));
      await _audit(actor, 'stock_count_apply', 'stock_count', countId.toString(),
          'lines=${lines.length}; adjusted=$adjusted');
      return adjusted;
    });
  }

  Future<void> cancelCount(Profile actor, int countId) async {
    _requireInventory(actor);
    await _db.transaction(() async {
      await (_db.update(_db.stockCounts)..where((t) => t.id.equals(countId)))
          .write(const StockCountsCompanion(
              status: Value(StockCountStatus.cancelled)));
      await _audit(actor, 'stock_count_cancel', 'stock_count',
          countId.toString(), 'cancelado');
    });
  }

  // ---------------------------------------------------------------------------
  // Stock bajo (punto de reorden por variante + default global)
  // ---------------------------------------------------------------------------
  Future<int> lowStockDefault() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(_lowStockDefaultKey)))
        .getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? lowStockDefaultFallback;
  }

  Future<void> setLowStockDefault(Profile actor, int value) async {
    _requireInventory(actor);
    if (value < 0) throw ArgumentError('El mínimo no puede ser negativo');
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
            key: _lowStockDefaultKey, value: value.toString()));
    await _audit(actor, 'set_low_stock_default', 'app_settings',
        _lowStockDefaultKey, 'value=$value');
  }

  Future<void> setVariantMinStock(
      Profile actor, int variantId, int? minStock) async {
    _requireInventory(actor);
    if (minStock != null && minStock < 0) {
      throw ArgumentError('El mínimo no puede ser negativo');
    }
    await _db.transaction(() async {
      await (_db.update(_db.variants)..where((t) => t.id.equals(variantId)))
          .write(VariantsCompanion(minStock: Value(minStock)));
      await _audit(actor, 'set_min_stock', 'variant', variantId.toString(),
          'minStock=${minStock ?? 'default'}');
    });
  }

  /// Variantes activas cuyo disponible (on_hand − reservado) está en o por
  /// debajo de su umbral (mínimo propio, o el default global si no tiene).
  /// Umbral 0 desactiva la alerta de esa variante.
  Future<List<LowStockItem>> lowStockVariants() async {
    final def = await lowStockDefault();
    final rows = await _db.customSelect(
      'SELECT v.id AS variant_id, p.id AS product_id, '
      'COALESCE(vs.on_hand, 0) - COALESCE(vs.reserved, 0) AS available, '
      'COALESCE(v.min_stock, ?1) AS threshold '
      'FROM variants v '
      'JOIN products p ON p.id = v.product_id '
      'LEFT JOIN variant_stock vs ON vs.variant_id = v.id '
      'WHERE v.active = 1 AND COALESCE(v.min_stock, ?1) > 0 '
      'AND (COALESCE(vs.on_hand, 0) - COALESCE(vs.reserved, 0)) <= COALESCE(v.min_stock, ?1) '
      'ORDER BY available ASC, p.name ASC',
      variables: [Variable.withInt(def)],
      readsFrom: {_db.variants, _db.products, _db.inventoryMovements},
    ).get();
    if (rows.isEmpty) return const [];

    final variantIds = rows.map((r) => r.read<int>('variant_id')).toList();
    final productIds = rows.map((r) => r.read<int>('product_id')).toSet().toList();
    final variants = {
      for (final v in await (_db.select(_db.variants)
            ..where((t) => t.id.isIn(variantIds)))
          .get())
        v.id: v,
    };
    final products = {
      for (final p in await (_db.select(_db.products)
            ..where((t) => t.id.isIn(productIds)))
          .get())
        p.id: p,
    };

    final out = <LowStockItem>[];
    for (final r in rows) {
      final v = variants[r.read<int>('variant_id')];
      final p = products[r.read<int>('product_id')];
      if (v == null || p == null) continue;
      out.add(LowStockItem(
        product: p,
        variant: v,
        available: r.read<int>('available'),
        threshold: r.read<int>('threshold'),
      ));
    }
    return out;
  }

  /// Cuántas variantes están bajo mínimo (para el badge de la campana).
  Future<int> lowStockCount() async {
    final def = await lowStockDefault();
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM variants v '
      'LEFT JOIN variant_stock vs ON vs.variant_id = v.id '
      'WHERE v.active = 1 AND COALESCE(v.min_stock, ?1) > 0 '
      'AND (COALESCE(vs.on_hand, 0) - COALESCE(vs.reserved, 0)) <= COALESCE(v.min_stock, ?1)',
      variables: [Variable.withInt(def)],
      readsFrom: {_db.variants, _db.inventoryMovements},
    ).getSingle();
    return row.read<int>('n');
  }

  // ---------------------------------------------------------------------------
  // Internos
  // ---------------------------------------------------------------------------
  Future<void> _audit(Profile actor, String action, String entityType,
          String? entityId, String detail) =>
      _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            detail: Value(detail),
          ));
}
