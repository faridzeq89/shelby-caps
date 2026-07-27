import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/demo_seed.dart';
import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('DemoSeedService carga 100 productos con imagen y stock', () async {
    final db = AppDatabase(NativeDatabase.memory());

    final n = await DemoSeedService(db).load(count: 100);
    expect(n, 100);

    final products = await db.select(db.products).get();
    expect(products, hasLength(100));
    // Todos referencian una imagen de demo.
    expect(
      products.every(
          (p) => p.imagePath != null && p.imagePath!.startsWith('assets/demo/')),
      isTrue,
    );

    // Se generaron variantes con stock disponible.
    final variants = await db.select(db.variants).get();
    expect(variants.length, greaterThan(100));
    final stock = await db.stockFor(variants.first.id);
    expect(stock.available, greaterThan(0));

    // Los códigos internos no colisionan (uno por variante).
    final barcodes = await db.select(db.barcodes).get();
    final codes = barcodes.map((b) => b.code).toSet();
    expect(codes.length, barcodes.length);

    await db.close();
  });

  test('cargar el demo dos veces no rompe (SKUs y códigos siguen únicos)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await DemoSeedService(db).load(count: 10);
    await DemoSeedService(db).load(count: 10);

    final products = await db.select(db.products).get();
    expect(products, hasLength(20));
    final barcodes = await db.select(db.barcodes).get();
    expect(barcodes.map((b) => b.code).toSet().length, barcodes.length);
    final variants = await db.select(db.variants).get();
    expect(variants.map((v) => v.sku).toSet().length, variants.length);

    await db.close();
  });
}
