import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Precio efectivo de una variante: su override o el precio base del producto.
int effectivePrice(Product product, Variant variant) =>
    variant.priceCentsOverride ?? product.basePriceCents;

/// Precio de **mayoreo** aplicable para [qty] unidades de un producto, dados
/// sus escalones [tiers]. Devuelve el precio del mayor escalón cuyo `minQty` ya
/// se alcanzó, o `null` si ninguno aplica (se usa el precio normal). El orden de
/// [tiers] no importa.
int? wholesalePriceFor(List<PriceTier> tiers, int qty) {
  int? best;
  var bestMin = -1;
  for (final t in tiers) {
    if (qty >= t.minQty && t.minQty > bestMin) {
      bestMin = t.minQty;
      best = t.priceCents;
    }
  }
  return best;
}

/// Operaciones de catálogo (lado administrador). Los cambios sensibles exigen
/// rol y quedan en `audit_log`.
class CatalogRepository {
  CatalogRepository(this._db);
  final AppDatabase _db;

  void _requireCatalog(Profile actor) {
    if (!Permissions.canManageCatalog(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede administrar el catálogo');
    }
  }

  // -------------------------------------------------------------------------
  // Lecturas
  // -------------------------------------------------------------------------
  Future<List<Category>> categories() =>
      (_db.select(_db.categories)..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  Future<List<Product>> products() =>
      (_db.select(_db.products)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  Future<Product?> productById(int id) =>
      (_db.select(_db.products)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Productos activos para la vitrina, opcionalmente filtrados por categoría
  /// ([categoryId] nulo = todas). Ordenados por nombre.
  Future<List<Product>> productsByCategory(int? categoryId, {int limit = 500}) {
    final q = _db.select(_db.products)
      ..where((t) => t.active.equals(true))
      ..orderBy([(t) => OrderingTerm(expression: t.name)])
      ..limit(limit);
    if (categoryId != null) {
      q.where((t) => t.categoryId.equals(categoryId));
    }
    return q.get();
  }

  Future<List<Variant>> variantsOf(int productId) =>
      (_db.select(_db.variants)..where((t) => t.productId.equals(productId)))
          .get();

  /// Escalones de mayoreo de un producto, ordenados por cantidad mínima.
  Future<List<PriceTier>> priceTiersOf(int productId) =>
      (_db.select(_db.priceTiers)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([(t) => OrderingTerm(expression: t.minQty)]))
          .get();

  Future<Variant?> variantById(int id) =>
      (_db.select(_db.variants)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<Barcode>> barcodesOf(int variantId) =>
      (_db.select(_db.barcodes)..where((t) => t.variantId.equals(variantId)))
          .get();

  /// Escaneo: devuelve la variante ligada a [code], o null si no existe.
  Future<Variant?> resolveByCode(String code) async {
    final bc = await (_db.select(_db.barcodes)
          ..where((t) => t.code.equals(code.trim())))
        .getSingleOrNull();
    if (bc == null) return null;
    return (_db.select(_db.variants)..where((t) => t.id.equals(bc.variantId)))
        .getSingleOrNull();
  }

  /// El producto padre de una variante.
  Future<Product?> productOfVariant(Variant variant) => productById(variant.productId);

  /// Búsqueda por nombre de producto o SKU (para agregar al carrito sin lector).
  Future<List<(Product, Variant)>> searchVariants(String query,
      {int limit = 40}) async {
    final q = '%${query.trim()}%';
    final rows = await (_db.select(_db.variants).join([
      innerJoin(_db.products,
          _db.products.id.equalsExp(_db.variants.productId)),
    ])
          ..where(_db.variants.sku.like(q) | _db.products.name.like(q))
          ..where(_db.variants.active.equals(true))
          ..limit(limit))
        .get();
    return rows
        .map((r) => (r.readTable(_db.products), r.readTable(_db.variants)))
        .toList();
  }

  /// Búsqueda por PRODUCTO (para el flujo tipo e-commerce: elegir la prenda y
  /// luego la variante). Coincide por nombre o por SKU de alguna variante.
  Future<List<Product>> searchProducts(String query, {int limit = 40}) async {
    final q = '%${query.trim()}%';
    final byName = await (_db.select(_db.products)
          ..where((t) => t.name.like(q) & t.active.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)])
          ..limit(limit))
        .get();
    final ids = byName.map((p) => p.id).toSet();
    final result = [...byName];

    final bySku = await (_db.select(_db.variants).join([
      innerJoin(_db.products,
          _db.products.id.equalsExp(_db.variants.productId)),
    ])
          ..where(_db.variants.sku.like(q) & _db.products.active.equals(true))
          ..limit(limit))
        .get();
    for (final r in bySku) {
      final p = r.readTable(_db.products);
      if (ids.add(p.id)) result.add(p);
    }
    return result;
  }

  /// Como [searchProducts] pero además coincide por **nombre de categoría**
  /// (para inventario: "buscar por nombre de producto o categoría").
  Future<List<Product>> searchProductsOrCategory(String query,
      {int limit = 60}) async {
    final result = await searchProducts(query, limit: limit);
    final ids = result.map((p) => p.id).toSet();
    final q = '%${query.trim()}%';
    final cats = await (_db.select(_db.categories)
          ..where((t) => t.name.like(q)))
        .get();
    for (final c in cats) {
      final prods = await productsByCategory(c.id, limit: limit);
      for (final p in prods) {
        if (ids.add(p.id)) result.add(p);
      }
    }
    return result;
  }

  /// Variantes activas de un producto con su existencia disponible (del ledger).
  Future<List<(Variant, int)>> variantsWithStock(int productId) async {
    final variants = await (_db.select(_db.variants)
          ..where((t) => t.productId.equals(productId) & t.active.equals(true)))
        .get();
    final out = <(Variant, int)>[];
    for (final v in variants) {
      out.add((v, (await _db.stockFor(v.id)).available));
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Altas
  // -------------------------------------------------------------------------
  Future<int> createCategory(Profile actor, String name) async {
    _requireCatalog(actor);
    final count = (await _db.select(_db.categories).get()).length;
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(name: name, sortOrder: Value(count)),
        );
  }

  Future<int> createProduct(
    Profile actor, {
    required String name,
    required int categoryId,
    required int basePriceCents,
    String? brand,
    int taxRateBps = 1600,
  }) async {
    _requireCatalog(actor);
    return _db.into(_db.products).insert(
          ProductsCompanion.insert(
            name: name,
            categoryId: categoryId,
            basePriceCents: basePriceCents,
            brand: Value(brand),
            taxRateBps: Value(taxRateBps),
          ),
        );
  }

  /// Genera en lote las variantes de la matriz talla × color que aún no
  /// existan, cada una con su código interno `MB` y, opcionalmente, stock
  /// inicial. Devuelve los ids creados. Esta es la función que carga el
  /// inventario en minutos en vez de horas.
  Future<List<int>> generateVariantMatrix(
    Profile actor, {
    required int productId,
    required List<String> sizes,
    required List<String> colors,
    int costCents = 0,
    int initialStock = 0,
    int? locationId,
  }) async {
    _requireCatalog(actor);
    final product = await productById(productId);
    if (product == null) return const [];

    final normSizes = _dedup(sizes);
    final normColors = _dedup(colors);

    return _db.transaction(() async {
      final existing = await variantsOf(productId);
      final existingKeys = existing
          .map((v) => _variantKey(v.size ?? '', v.color ?? ''))
          .toSet();
      var seq = await _maxInternalBarcodeNumber();
      final created = <int>[];

      for (final size in normSizes) {
        for (final color in normColors) {
          if (existingKeys.contains(_variantKey(size, color))) continue;
          final variantId = await _db.into(_db.variants).insert(
                VariantsCompanion.insert(
                  productId: productId,
                  sku: _sku(productId, size, color),
                  size: Value(size),
                  color: Value(color),
                  costCents: Value(costCents),
                ),
              );
          seq++;
          await _db.into(_db.barcodes).insert(
                BarcodesCompanion.insert(
                  variantId: variantId,
                  code: 'MB${seq.toString().padLeft(10, '0')}',
                  source: BarcodeSource.internal,
                ),
              );
          if (initialStock > 0 && locationId != null) {
            await _db.into(_db.inventoryMovements).insert(
                  InventoryMovementsCompanion.insert(
                    variantId: variantId,
                    locationId: locationId,
                    qty: initialStock,
                    type: MovementType.receipt,
                    userId: Value(actor.id),
                    reason: const Value('Alta de variante'),
                  ),
                );
          }
          created.add(variantId);
        }
      }
      return created;
    });
  }

  /// Vincula un código de proveedor (UPC escaneado o tecleado) a una variante.
  Future<int> addSupplierBarcode(
    Profile actor,
    int variantId,
    String code,
  ) async {
    _requireCatalog(actor);
    return _db.into(_db.barcodes).insert(
          BarcodesCompanion.insert(
            variantId: variantId,
            code: code.trim(),
            source: BarcodeSource.supplier,
          ),
        );
  }

  // -------------------------------------------------------------------------
  // Precios y costos (con auditoría)
  // -------------------------------------------------------------------------
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
      await _audit(actor, 'update_price', 'variant', variantId.toString(),
          'priceCents=$newPriceCents');
    });
  }

  Future<void> updateVariantCost({
    required Profile actor,
    required int variantId,
    required int newCostCents,
  }) async {
    _requireCatalog(actor);
    await _db.transaction(() async {
      await (_db.update(_db.variants)..where((t) => t.id.equals(variantId)))
          .write(VariantsCompanion(costCents: Value(newCostCents)));
      await _audit(actor, 'update_cost', 'variant', variantId.toString(),
          'costCents=$newCostCents');
    });
  }

  /// Reemplaza TODOS los escalones de mayoreo de un producto por [tiers] (lista
  /// vacía = quitar el mayoreo). Cada escalón es `(minQty, priceCents)`. Exige
  /// permiso de precios y queda en auditoría. Ignora escalones con `minQty<=1` o
  /// `priceCents<0`, y deduplica por `minQty` (gana el último).
  Future<void> setPriceTiers({
    required Profile actor,
    required int productId,
    required List<({int minQty, int priceCents})> tiers,
  }) async {
    if (!Permissions.canEditPrices(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede editar precios');
    }
    final clean = <int, int>{}; // minQty -> priceCents
    for (final t in tiers) {
      if (t.minQty <= 1 || t.priceCents < 0) continue;
      clean[t.minQty] = t.priceCents;
    }
    await _db.transaction(() async {
      await (_db.delete(_db.priceTiers)
            ..where((t) => t.productId.equals(productId)))
          .go();
      for (final entry in clean.entries) {
        await _db.into(_db.priceTiers).insert(
              PriceTiersCompanion.insert(
                productId: productId,
                minQty: entry.key,
                priceCents: entry.value,
              ),
            );
      }
      await _audit(actor, 'set_price_tiers', 'product', productId.toString(),
          '${clean.length} escalones');
    });
  }

  Future<void> updateProductBasePrice({
    required Profile actor,
    required int productId,
    required int newPriceCents,
  }) async {
    if (!Permissions.canEditPrices(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede editar precios');
    }
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(basePriceCents: Value(newPriceCents)));
      await _audit(actor, 'update_price', 'product', productId.toString(),
          'basePriceCents=$newPriceCents');
    });
  }

  /// Liga (o desliga con [supplierId] nulo) un proveedor al producto.
  Future<void> updateProductSupplier({
    required Profile actor,
    required int productId,
    required int? supplierId,
  }) async {
    _requireCatalog(actor);
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(supplierId: Value(supplierId)));
      await _audit(actor, 'update_supplier', 'product', productId.toString(),
          supplierId == null ? 'sin proveedor' : 'proveedor=$supplierId');
    });
  }

  /// Guarda (o quita, con [path] nulo) la ruta de imagen del producto. La
  /// optimización y el archivo los maneja la capa de UI (ImageService).
  Future<void> updateProductImage({
    required Profile actor,
    required int productId,
    required String? path,
  }) async {
    _requireCatalog(actor);
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(imagePath: Value(path)));
      await _audit(actor, 'update_image', 'product', productId.toString(),
          path == null ? 'sin imagen' : 'imagen actualizada');
    });
  }

  // -------------------------------------------------------------------------
  // Archivar / borrar producto
  // -------------------------------------------------------------------------

  /// Archiva (o reactiva con [active]=true) un producto y TODAS sus variantes.
  /// Soft-delete: sale de la vitrina y de la búsqueda, pero conserva el historial
  /// (ventas, ledger). Reversible. Es la vía correcta para "quitar" un producto
  /// que ya se vendió o tiene movimientos de inventario.
  Future<void> setProductActive(
      Profile actor, int productId, bool active) async {
    _requireCatalog(actor);
    await _db.transaction(() async {
      await (_db.update(_db.products)..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(active: Value(active)));
      await (_db.update(_db.variants)
            ..where((t) => t.productId.equals(productId)))
          .write(VariantsCompanion(active: Value(active)));
      await _audit(actor, active ? 'reactivate' : 'archive', 'product',
          productId.toString(), active ? 'reactivado' : 'archivado');
    });
  }

  /// ¿El producto tiene VENTAS (líneas de venta en alguna de sus variantes)?
  Future<bool> productHasSales(int productId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM sale_lines sl '
      'JOIN variants v ON v.id = sl.variant_id WHERE v.product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {_db.saleLines, _db.variants},
    ).getSingle();
    return row.read<int>('n') > 0;
  }

  /// ¿El producto tiene MOVIMIENTOS de inventario? El ledger es append-only e
  /// INMUTABLE (triggers): si hay movimientos, el producto NO se puede borrar de
  /// verdad — solo archivar.
  Future<bool> productHasMovements(int productId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM inventory_movements m '
      'JOIN variants v ON v.id = m.variant_id WHERE v.product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {_db.inventoryMovements, _db.variants},
    ).getSingle();
    return row.read<int>('n') > 0;
  }

  /// True si el producto se puede BORRAR de verdad: sin ventas y sin movimientos
  /// de inventario (p. ej. un alta por error). Si no, archívalo.
  Future<bool> canDeleteProduct(int productId) async {
    return !(await productHasSales(productId)) &&
        !(await productHasMovements(productId));
  }

  /// Borrado REAL. Solo para productos SIN ventas ni movimientos de inventario.
  /// Si tiene historial lanza [StateError] (el historial es inmutable): en ese
  /// caso usa [setProductActive] para archivar. Borra códigos, variantes y el
  /// producto en una transacción.
  Future<void> deleteProduct(Profile actor, int productId) async {
    _requireCatalog(actor);
    if (!await canDeleteProduct(productId)) {
      throw StateError(
          'El producto tiene ventas o movimientos de inventario y no se puede '
          'borrar (el historial es inmutable). Archívalo en su lugar.');
    }
    await _db.transaction(() async {
      final vs = await variantsOf(productId);
      for (final v in vs) {
        await (_db.delete(_db.barcodes)..where((t) => t.variantId.equals(v.id)))
            .go();
        await (_db.delete(_db.stockCountLines)
              ..where((t) => t.variantId.equals(v.id)))
            .go();
        await (_db.delete(_db.variants)..where((t) => t.id.equals(v.id))).go();
      }
      await (_db.delete(_db.priceTiers)
            ..where((t) => t.productId.equals(productId)))
          .go();
      await (_db.delete(_db.products)..where((t) => t.id.equals(productId))).go();
      await _audit(actor, 'delete', 'product', productId.toString(), 'borrado');
    });
  }

  // -------------------------------------------------------------------------
  // Internos
  // -------------------------------------------------------------------------
  Future<void> _audit(Profile actor, String action, String entityType,
      String entityId, String detail) {
    return _db.into(_db.auditLog).insert(
          AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: entityType,
            entityId: Value(entityId),
            detail: Value(detail),
          ),
        );
  }

  /// Mayor número usado en los códigos internos `MB##########`, para continuar
  /// sin colisiones con lo ya sembrado.
  Future<int> _maxInternalBarcodeNumber() async {
    final row = await _db
        .customSelect(
          "SELECT COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0) AS n "
          "FROM barcodes WHERE source = 'internal'",
          readsFrom: {_db.barcodes},
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Deduplica tallas/colores de un lote (sin distinguir mayúsculas, espacios
  /// ni acentos), evitando SKUs repetidos en la misma generación.
  List<String> _dedup(List<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final t = raw.trim();
      if (t.isEmpty) continue;
      if (seen.add(_san(t))) out.add(t);
    }
    return out;
  }

  String _variantKey(String size, String color) =>
      '${_san(size)}|${_san(color)}';

  String _san(String v) =>
      v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// SKU único por (producto, talla, color): `P{id}-{TALLA}-{COLOR}`. No es
  /// lossy, así que dos colores distintos nunca colisionan.
  String _sku(int productId, String size, String color) =>
      'P$productId-${_san(size)}-${_san(color)}';
}
