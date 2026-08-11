import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v10→v11 crea quotes/quote_lines sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v11');
    final file = File(p.join(dir.path, 'test.sqlite'));

    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.customers).insert(CustomersCompanion.insert(name: 'Ana'));
    await db.close();

    // Simula v10: sin tablas de cotización y user_version = 10.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS quote_lines');
    raw.execute('DROP TABLE IF EXISTS quotes');
    raw.execute('PRAGMA user_version = 10');
    raw.close();

    db = AppDatabase(NativeDatabase(file));
    final customers = await db.select(db.customers).get();
    expect(customers.single.name, 'Ana');

    // Variante real para respetar la FK de quote_lines.
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: catId, basePriceCents: 10000));
    final vid = await db
        .into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: 'A'));

    final qid = await db.into(db.quotes).insert(QuotesCompanion.insert(
        folio: 'COT-000001',
        status: QuoteStatus.open,
        subtotalCents: 10000,
        totalCents: 10000));
    await db.into(db.quoteLines).insert(QuoteLinesCompanion.insert(
        quoteId: qid, variantId: vid, qty: 1, unitPriceCents: 10000, lineTotalCents: 10000));
    expect(await db.select(db.quoteLines).get(), hasLength(1));

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
