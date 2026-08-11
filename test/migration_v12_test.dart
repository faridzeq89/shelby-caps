import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v11→v12 crea suppliers y products.supplier_id sin perder datos',
      () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v12');
    final file = File(p.join(dir.path, 'test.sqlite'));

    var db = AppDatabase(NativeDatabase(file));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Gorra', categoryId: catId, basePriceCents: 10000));
    await db.close();

    // Simula v11: sin suppliers, sin products.supplier_id, user_version = 11.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS suppliers');
    raw.execute('ALTER TABLE products DROP COLUMN supplier_id');
    raw.execute('PRAGMA user_version = 11');
    raw.close();

    // Reabrir → onUpgrade v11→v12.
    db = AppDatabase(NativeDatabase(file));
    final products = await db.select(db.products).get();
    expect(products.single.name, 'Gorra');
    expect(products.single.supplierId, isNull);

    final sid = await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(name: 'Prov'));
    expect((await db.select(db.suppliers).get()).single.id, sid);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
