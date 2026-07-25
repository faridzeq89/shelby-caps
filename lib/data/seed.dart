import 'package:drift/drift.dart';

import 'local/database.dart';

/// Plantilla de producto para generar la matriz talla × color.
class _Template {
  const _Template(
    this.name,
    this.category,
    this.brand,
    this.priceCents,
    this.costCents,
    this.sizes,
    this.colors, {
    this.stockPerVariant = 6,
    this.withSupplierCode = false,
  });

  final String name;
  final String category;
  final String brand;
  final int priceCents;
  final int costCents;
  final List<String> sizes;
  final List<String> colors;
  final int stockPerVariant;
  final bool withSupplierCode;
}

const _catalog = <_Template>[
  _Template('Blusa manga corta', 'Blusas', 'Aurora', 24900, 11000,
      ['CH', 'M', 'G', 'XG'], ['Blanco', 'Negro', 'Rosa'],
      withSupplierCode: true),
  _Template('Blusa de encaje', 'Blusas', 'Aurora', 32900, 15000,
      ['CH', 'M', 'G'], ['Blanco', 'Vino']),
  _Template('Camisa lino', 'Blusas', 'Lino & Co', 39900, 18500,
      ['CH', 'M', 'G', 'XG'], ['Beige', 'Azul cielo']),
  _Template('Vestido casual', 'Vestidos', 'Aurora', 45900, 21000,
      ['CH', 'M', 'G'], ['Negro', 'Rojo', 'Floral']),
  _Template('Vestido de fiesta', 'Vestidos', 'Gala', 89900, 42000,
      ['CH', 'M', 'G', 'XG'], ['Negro', 'Azul marino'],
      stockPerVariant: 3),
  _Template('Pantalón mezclilla', 'Pantalones', 'Denim City', 54900, 26000,
      ['28', '30', '32', '34'], ['Azul', 'Negro'], withSupplierCode: true),
  _Template('Pantalón vestir', 'Pantalones', 'Ejecutiva', 49900, 23000,
      ['28', '30', '32'], ['Gris', 'Negro']),
  _Template('Playera básica', 'Playeras', 'BasicWear', 15900, 6500,
      ['CH', 'M', 'G', 'XG'], ['Blanco', 'Negro', 'Gris', 'Rosa'],
      stockPerVariant: 10),
  _Template('Playera estampada', 'Playeras', 'BasicWear', 19900, 8000,
      ['CH', 'M', 'G'], ['Blanco', 'Negro']),
  _Template('Suéter tejido', 'Suéteres', 'Abrigo', 42900, 20000,
      ['CH', 'M', 'G'], ['Beige', 'Café', 'Verde']),
  _Template('Chamarra ligera', 'Suéteres', 'Abrigo', 69900, 33000,
      ['CH', 'M', 'G', 'XG'], ['Negro', 'Camel'], stockPerVariant: 4),
  _Template('Falda plisada', 'Faldas', 'Aurora', 29900, 13000,
      ['CH', 'M', 'G'], ['Negro', 'Vino', 'Mostaza']),
];

/// Siembra base operativa y, si el catálogo está vacío, mercancía de ejemplo.
class SeedService {
  SeedService(this._db);
  final AppDatabase _db;

  static const defaultDevicePrefix = 'T1';

  Future<int> run() async {
    final locationId = await _ensureLocation();
    await _ensureDevicePrefix();

    final hasProducts = (await _db.select(_db.products).get()).isNotEmpty;
    if (hasProducts) return locationId;

    await _seedCatalog(locationId);
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

  Future<void> _seedCatalog(int locationId) async {
    var internalSeq = 1;

    // Categorías (deduplicadas por nombre en orden de aparición).
    final categoryIds = <String, int>{};
    for (final t in _catalog) {
      categoryIds.putIfAbsent(
        t.category,
        () => -1,
      );
    }
    var order = 0;
    for (final name in categoryIds.keys.toList()) {
      categoryIds[name] = await _db.into(_db.categories).insert(
            CategoriesCompanion.insert(name: name, sortOrder: Value(order++)),
          );
    }

    for (final t in _catalog) {
      final productId = await _db.into(_db.products).insert(
            ProductsCompanion.insert(
              name: t.name,
              categoryId: categoryIds[t.category]!,
              basePriceCents: t.priceCents,
              brand: Value(t.brand),
            ),
          );

      for (final size in t.sizes) {
        for (final color in t.colors) {
          final sku = _sku(t, productId, size, color);
          final variantId = await _db.into(_db.variants).insert(
                VariantsCompanion.insert(
                  productId: productId,
                  sku: sku,
                  size: Value(size),
                  color: Value(color),
                  costCents: Value(t.costCents),
                ),
              );

          final internal = 'MB${internalSeq.toString().padLeft(10, '0')}';
          internalSeq++;
          await _db.into(_db.barcodes).insert(
                BarcodesCompanion.insert(
                  variantId: variantId,
                  code: internal,
                  source: BarcodeSource.internal,
                ),
              );
          if (t.withSupplierCode) {
            await _db.into(_db.barcodes).insert(
                  BarcodesCompanion.insert(
                    variantId: variantId,
                    code: '75010${internalSeq.toString().padLeft(8, '0')}',
                    source: BarcodeSource.supplier,
                  ),
                );
          }

          // Stock inicial como entrada de mercancía (receipt).
          await _db.into(_db.inventoryMovements).insert(
                InventoryMovementsCompanion.insert(
                  variantId: variantId,
                  locationId: locationId,
                  qty: t.stockPerVariant,
                  type: MovementType.receipt,
                  reason: const Value('Stock inicial (semilla)'),
                ),
              );
        }
      }
    }
  }

  String _sku(_Template t, int productId, String size, String color) {
    String slug(String s) => s
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .padRight(3, 'X')
        .substring(0, 3);
    return '${slug(t.name)}-$productId-$size-${slug(color)}';
  }
}
