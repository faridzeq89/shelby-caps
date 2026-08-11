import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/catalog_sync_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Product> product(int catId, String name, int price) async {
    final id = await db.into(db.products).insert(ProductsCompanion.insert(
        name: name, categoryId: catId, basePriceCents: price));
    return (db.select(db.products)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<Variant> variant(int productId, String sku, {int? override}) async {
    final id = await db.into(db.variants).insert(VariantsCompanion.insert(
        productId: productId,
        sku: sku,
        priceCentsOverride: Value(override)));
    return (db.select(db.variants)..where((t) => t.id.equals(id))).getSingle();
  }

  test('buildSnapshot arma productos, variantes (precio efectivo) y mayoreo', () async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Gorras'));
    final p = await product(catId, 'Shelby', 20000);
    final vBase = await variant(p.id, 'A'); // hereda 20000
    final vOver = await variant(p.id, 'B', override: 18000); // override

    final snap = CatalogSyncService.buildSnapshot(
      products: [p],
      categoryNames: {catId: 'Gorras'},
      variants: [
        (variant: vBase, stock: 5),
        (variant: vOver, stock: 3),
      ],
      tiers: [
        PriceTier(id: 1, productId: p.id, minQty: 10, priceCents: 15000, createdAt: DateTime(2026)),
      ],
    );

    expect(snap.products, hasLength(1));
    expect(snap.products.single['name'], 'Shelby');
    expect(snap.products.single['category'], 'Gorras');

    expect(snap.variants, hasLength(2));
    final a = snap.variants.firstWhere((v) => v['sku'] == 'A');
    final b = snap.variants.firstWhere((v) => v['sku'] == 'B');
    expect(a['price_cents'], 20000); // hereda base
    expect(a['stock'], 5);
    expect(b['price_cents'], 18000); // override

    expect(snap.tiers, hasLength(1));
    expect(snap.tiers.single['min_qty'], 10);
    expect(snap.tiers.single['price_cents'], 15000);
  });

  test('descarta variantes/tiers de productos que no van en el snapshot', () async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final p = await product(catId, 'A', 10000);
    final v = await variant(p.id, 'A');

    // Variante y tier de un producto "fantasma" (id 999) no incluido.
    final ghost = Variant(
        id: 50,
        productId: 999,
        sku: 'GHOST',
        priceCentsOverride: null,
        costCents: 0,
        active: true,
        createdAt: DateTime(2026));

    final snap = CatalogSyncService.buildSnapshot(
      products: [p],
      categoryNames: {catId: 'C'},
      variants: [(variant: v, stock: 1), (variant: ghost, stock: 1)],
      tiers: [
        PriceTier(id: 1, productId: 999, minQty: 10, priceCents: 1, createdAt: DateTime(2026)),
      ],
    );

    expect(snap.variants, hasLength(1));
    expect(snap.variants.single['sku'], 'A');
    expect(snap.tiers, isEmpty);
  });
}
