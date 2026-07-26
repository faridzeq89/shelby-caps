import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v3→v4 agrega variants.min_stock sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v4');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Crea la base actual (v4) con un producto y una variante con mínimo.
    var db = AppDatabase(NativeDatabase(file));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'P', categoryId: catId, basePriceCents: 1000));
    await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: prodId, sku: 'SKU-1'));
    await db.close();

    // 2) Simula una base v3: quita min_stock y baja el user_version.
    final raw = sqlite3.open(file.path);
    // SQLite no soporta DROP COLUMN en versiones viejas; recrea sin la columna.
    raw.execute('ALTER TABLE variants RENAME TO variants_old');
    raw.execute('''
      CREATE TABLE variants (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products (id),
        sku TEXT NOT NULL UNIQUE,
        size TEXT NULL,
        color TEXT NULL,
        attributes TEXT NULL,
        price_cents_override INTEGER NULL,
        cost_cents INTEGER NOT NULL DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    raw.execute('''
      INSERT INTO variants (id, product_id, sku, size, color, attributes,
        price_cents_override, cost_cents, active, created_at)
      SELECT id, product_id, sku, size, color, attributes,
        price_cents_override, cost_cents, active, created_at FROM variants_old
    ''');
    raw.execute('DROP TABLE variants_old');
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    // 3) Reabre: debe correr onUpgrade v3→v4 y agregar la columna.
    db = AppDatabase(NativeDatabase(file));
    final variants = await db.select(db.variants).get();
    expect(variants, hasLength(1));
    expect(variants.single.sku, 'SKU-1');
    expect(variants.single.minStock, isNull); // columna nueva, nula por defecto

    // La columna ya es utilizable.
    await (db.update(db.variants)..where((t) => t.id.equals(variants.single.id)))
        .write(const VariantsCompanion(minStock: Value(4)));
    final updated = await db.select(db.variants).get();
    expect(updated.single.minStock, 4);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
