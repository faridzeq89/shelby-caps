import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v4→v5 agrega products.image_path sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v5');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Crea la base actual (v5) con una categoría y un producto.
    var db = AppDatabase(NativeDatabase(file));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Blusa', categoryId: catId, basePriceCents: 34900));
    await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: prodId, sku: 'SKU-1'));
    await db.close();

    // 2) Simula una base v4: recrea products sin image_path y baja user_version.
    final raw = sqlite3.open(file.path);
    raw.execute('ALTER TABLE products RENAME TO products_old');
    raw.execute('''
      CREATE TABLE products (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER NOT NULL REFERENCES categories (id),
        brand TEXT NULL,
        description TEXT NULL,
        base_price_cents INTEGER NOT NULL,
        tax_rate_bps INTEGER NOT NULL DEFAULT 1600,
        active INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      )
    ''');
    raw.execute('''
      INSERT INTO products (id, name, category_id, brand, description,
        base_price_cents, tax_rate_bps, active, created_at)
      SELECT id, name, category_id, brand, description,
        base_price_cents, tax_rate_bps, active, created_at FROM products_old
    ''');
    raw.execute('DROP TABLE products_old');
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    // 3) Reabre: debe correr onUpgrade v4→v5 y agregar la columna.
    db = AppDatabase(NativeDatabase(file));
    final products = await db.select(db.products).get();
    expect(products, hasLength(1));
    expect(products.single.name, 'Blusa');
    expect(products.single.imagePath, isNull); // columna nueva, nula por defecto

    // La columna ya es utilizable.
    await (db.update(db.products)..where((t) => t.id.equals(products.single.id)))
        .write(const ProductsCompanion(imagePath: Value('assets/demo/blusa.webp')));
    final updated = await db.select(db.products).get();
    expect(updated.single.imagePath, 'assets/demo/blusa.webp');

    // Las variantes siguen intactas (la migración no las tocó).
    final variants = await db.select(db.variants).get();
    expect(variants.single.sku, 'SKU-1');

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
