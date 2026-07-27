import 'package:drift/drift.dart';

import 'local/database.dart';

/// Genera un catálogo de PRUEBA de ~100 productos con variantes talla×color,
/// stock inicial e imágenes de demo (assets `assets/demo/pNN.jpg`). Sirve para
/// evaluar el rediseño visual y el rendimiento con muchos mosaicos. No es para
/// producción: el dueño lo carga a mano desde Admin y puede empezar de cero.
class DemoSeedService {
  DemoSeedService(this._db);
  final AppDatabase _db;

  static const int demoImageCount = 24; // p01..p24 en assets/demo

  static const _adjectives = [
    'Clásica', 'Moderna', 'Elegante', 'Casual', 'Premium', 'Urbana',
    'Vintage', 'Boho', 'Chic', 'Deportiva', 'Primavera', 'Verano',
    'Otoño', 'Slim', 'Oversize', 'Estampada', 'Lisa', 'Bordada',
    'Floral', 'Minimal',
  ];

  static const _cats = <_DemoCat>[
    _DemoCat('Blusas', 'Blusa', ['CH', 'M', 'G', 'XG'],
        ['Blanco', 'Negro', 'Rosa'], 24900, 39900),
    _DemoCat('Vestidos', 'Vestido', ['CH', 'M', 'G'],
        ['Negro', 'Rojo', 'Azul marino'], 45900, 99900),
    _DemoCat('Pantalones', 'Pantalón', ['28', '30', '32', '34'],
        ['Azul', 'Negro', 'Beige'], 49900, 69900),
    _DemoCat('Playeras', 'Playera', ['CH', 'M', 'G', 'XG'],
        ['Blanco', 'Negro', 'Gris'], 15900, 24900),
    _DemoCat('Suéteres', 'Suéter', ['CH', 'M', 'G'],
        ['Beige', 'Café', 'Camel'], 39900, 59900),
    _DemoCat('Faldas', 'Falda', ['CH', 'M', 'G'],
        ['Negro', 'Vino', 'Mostaza'], 29900, 44900),
    _DemoCat('Chamarras', 'Chamarra', ['CH', 'M', 'G', 'XG'],
        ['Negro', 'Camel', 'Azul'], 69900, 119900),
    _DemoCat('Accesorios', 'Bolsa', ['Única'],
        ['Negro', 'Café', 'Multicolor'], 19900, 49900),
  ];

  /// Carga [count] productos. Devuelve cuántos productos creó. Idempotente por
  /// diseño de SKU/códigos (continúa la numeración interna existente).
  Future<int> load({int count = 100}) async {
    final locationId = await _ensureLocation();
    final categoryIds = await _ensureCategories();
    var seq = await _maxInternalSeq();

    return _db.transaction(() async {
      var created = 0;
      for (var i = 0; i < count; i++) {
        final cat = _cats[i % _cats.length];
        final adj = _adjectives[i % _adjectives.length];
        final name = '${cat.base} $adj ${i + 1}';
        final price = cat.minPrice +
            ((cat.maxPrice - cat.minPrice) ~/ 100) * ((i * 37) % 100);
        final cost = (price * 0.45).round();
        final imagePath = 'assets/demo/p${((i % demoImageCount) + 1).toString().padLeft(2, '0')}.jpg';

        final productId = await _db.into(_db.products).insert(
              ProductsCompanion.insert(
                name: name,
                categoryId: categoryIds[cat.name]!,
                basePriceCents: price,
                brand: const Value('Demo'),
                imagePath: Value(imagePath),
              ),
            );

        // Limita colores a 3 para no inflar el número de variantes.
        final colors = cat.colors.take(3).toList();
        for (final size in cat.sizes) {
          for (final color in colors) {
            final variantId = await _db.into(_db.variants).insert(
                  VariantsCompanion.insert(
                    productId: productId,
                    sku: 'P$productId-${_slug(size)}-${_slug(color)}',
                    size: Value(size),
                    color: Value(color),
                    costCents: Value(cost),
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
            await _db.into(_db.inventoryMovements).insert(
                  InventoryMovementsCompanion.insert(
                    variantId: variantId,
                    locationId: locationId,
                    qty: 5 + ((i + size.length) % 8),
                    type: MovementType.receipt,
                    reason: const Value('Catálogo de prueba'),
                  ),
                );
          }
        }
        created++;
      }
      return created;
    });
  }

  Future<int> _ensureLocation() async {
    final existing = await _db.select(_db.locations).get();
    if (existing.isNotEmpty) return existing.first.id;
    return _db.into(_db.locations).insert(
          LocationsCompanion.insert(name: 'Principal'),
        );
  }

  Future<Map<String, int>> _ensureCategories() async {
    final existing = await _db.select(_db.categories).get();
    final byName = {for (final c in existing) c.name: c.id};
    var order = existing.length;
    for (final cat in _cats) {
      if (!byName.containsKey(cat.name)) {
        byName[cat.name] = await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(
                  name: cat.name, sortOrder: Value(order++)),
            );
      }
    }
    return byName;
  }

  Future<int> _maxInternalSeq() async {
    final row = await _db.customSelect(
      "SELECT COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0) AS n "
      "FROM barcodes WHERE source = 'internal'",
      readsFrom: {_db.barcodes},
    ).getSingle();
    return row.read<int>('n');
  }

  String _slug(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

class _DemoCat {
  const _DemoCat(
      this.name, this.base, this.sizes, this.colors, this.minPrice, this.maxPrice);
  final String name;
  final String base;
  final List<String> sizes;
  final List<String> colors;
  final int minPrice;
  final int maxPrice;
}
