import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  // El mayoreo pasó de escalones por producto (tabla `price_tiers`) a un precio
  // único por producto (`products.wholesale_price_cents`) activado por el total
  // del carrito. Esta prueba verifica la migración v17→v18: convierte los
  // escalones al MENOR precio, descarta lo que no sea menor al menudeo y borra
  // la tabla vieja.
  test('migración v17→v18 convierte escalones a precio único y borra la tabla',
      () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v18');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Base actual (v18): tiene la columna nueva y NO tiene price_tiers.
    var db = AppDatabase(NativeDatabase(file));
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'Gorras'));
    final pOk = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Con mayoreo', categoryId: catId, basePriceCents: 20000));
    final pBad = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Mayoreo inválido', categoryId: catId, basePriceCents: 20000));
    await db.close();

    // 2) Simula una base v17: recrea price_tiers con datos y baja user_version.
    final raw = sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE price_tiers (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        min_qty INTEGER NOT NULL,
        price_cents INTEGER NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
      )''');
    // Dos escalones para el producto bueno: gana el MENOR (12000).
    raw.execute('INSERT INTO price_tiers (product_id, min_qty, price_cents) '
        'VALUES ($pOk, 10, 15000), ($pOk, 50, 12000)');
    // Un "mayoreo" que NO es menor al menudeo: debe quedar en null.
    raw.execute('INSERT INTO price_tiers (product_id, min_qty, price_cents) '
        'VALUES ($pBad, 10, 25000)');
    raw.execute('PRAGMA user_version = 17');
    raw.close();

    // 3) Reabrir → corre onUpgrade v17→v18.
    db = AppDatabase(NativeDatabase(file));

    final ok = await (db.select(db.products)..where((t) => t.id.equals(pOk)))
        .getSingle();
    expect(ok.wholesalePriceCents, 12000, reason: 'toma el menor escalón');

    final bad = await (db.select(db.products)..where((t) => t.id.equals(pBad)))
        .getSingle();
    expect(bad.wholesalePriceCents, isNull,
        reason: 'un mayoreo >= menudeo no sobrevive');

    // La tabla vieja ya no existe.
    final exists = db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='price_tiers'")
        .get();
    expect(await exists, isEmpty);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
