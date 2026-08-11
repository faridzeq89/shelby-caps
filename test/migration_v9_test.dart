import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v8→v9 crea price_tiers sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v9');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Base actual (v9) con una categoría/producto que deben sobrevivir.
    var db = AppDatabase(NativeDatabase(file));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Gorras'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Shelby', categoryId: catId, basePriceCents: 20000));
    await db.close();

    // 2) Simula una base v8: sin price_tiers y user_version = 8.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS price_tiers');
    raw.execute('PRAGMA user_version = 8');
    raw.close();

    // 3) Reabrir → corre onUpgrade v8→v9 y crea la tabla.
    db = AppDatabase(NativeDatabase(file));
    final products = await db.select(db.products).get();
    expect(products, hasLength(1));
    expect(products.single.name, 'Shelby');

    // La tabla nueva ya es utilizable.
    await db.into(db.priceTiers).insert(
        PriceTiersCompanion.insert(productId: pid, minQty: 10, priceCents: 15000));
    final tiers = await db.select(db.priceTiers).get();
    expect(tiers.single.minQty, 10);
    expect(tiers.single.priceCents, 15000);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
