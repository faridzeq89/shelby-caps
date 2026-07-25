import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v1→v2: conserva profiles y crea el resto del esquema',
      () async {
    // Simula la base instalada en Fase 1: solo `profiles` y user_version = 1.
    final executor = NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE profiles (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          role TEXT NOT NULL,
          pin_salt TEXT NOT NULL,
          pin_hash TEXT NOT NULL,
          must_change_pin INTEGER NOT NULL DEFAULT 0,
          active INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL DEFAULT (unixepoch())
        )
      ''');
      raw.execute(
          "INSERT INTO profiles (name, role, pin_salt, pin_hash) "
          "VALUES ('Administrador','admin','salt','hash')");
      raw.execute('PRAGMA user_version = 1');
    });

    final db = AppDatabase(executor);

    // El admin de la Fase 1 sobrevive a la migración.
    final profiles = await db.allProfiles();
    expect(profiles, hasLength(1));
    expect(profiles.first.name, 'Administrador');

    // Y las tablas nuevas ya existen y funcionan.
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: catId, basePriceCents: 1000));
    final varId = await db
        .into(db.variants)
        .insert(VariantsCompanion.insert(productId: prodId, sku: 'S1'));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: varId,
        locationId: locId,
        qty: 4,
        type: MovementType.receipt));

    // La vista variant_stock también quedó creada por la migración.
    final stock = await db.stockFor(varId);
    expect(stock.onHand, 4);

    await db.close();
  });
}
