import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v9→v10 crea expenses sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v10');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Base actual (v10) con un cliente que debe sobrevivir.
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.customers).insert(CustomersCompanion.insert(name: 'Ana'));
    await db.close();

    // 2) Simula una base v9: sin expenses y user_version = 9.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS expenses');
    raw.execute('PRAGMA user_version = 9');
    raw.close();

    // 3) Reabrir → corre onUpgrade v9→v10 y crea la tabla.
    db = AppDatabase(NativeDatabase(file));
    final customers = await db.select(db.customers).get();
    expect(customers.single.name, 'Ana');

    await db.into(db.expenses).insert(
        ExpensesCompanion.insert(category: 'Renta', amountCents: 500000));
    final expenses = await db.select(db.expenses).get();
    expect(expenses.single.amountCents, 500000);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
