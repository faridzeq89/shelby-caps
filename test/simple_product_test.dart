import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';

/// Alta de producto en un solo paso: en gorras casi todo es talla única, así
/// que crear el producto debe dejarlo **listo para vender** — con su variante,
/// su código, su costo y su existencia inicial— sin pasar por Inventario.
void main() {
  late AppDatabase db;
  late CatalogRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CatalogRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> admin() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Admin', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('crea producto, variante, código, costo y existencias de un jalón',
      () async {
    final actor = await admin();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId = await repo.createCategory(actor, 'Gorras');

    final productId = await repo.createSimpleProduct(
      actor,
      name: 'NY YANKEES NEGRA',
      categoryId: catId,
      basePriceCents: 60000,
      brand: 'Shelby',
      costCents: 27000,
      initialStock: 9,
      locationId: locId,
    );

    final variants = await repo.variantsOf(productId);
    expect(variants.length, 1, reason: 'talla única: una sola variante');
    expect(variants.single.costCents, 27000);

    final stock = await db.stockFor(variants.single.id);
    expect(stock.available, 9, reason: 'la existencia inicial ya quedó cargada');

    final codes = await repo.barcodesOf(variants.single.id);
    expect(codes.single.source, BarcodeSource.internal,
        reason: 'sale con código para escanear desde el primer día');
  });

  test('sin existencias no inventa movimientos de inventario', () async {
    final actor = await admin();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId = await repo.createCategory(actor, 'Gorras');

    final productId = await repo.createSimpleProduct(
      actor,
      name: 'Gorra en pedido',
      categoryId: catId,
      basePriceCents: 50000,
      locationId: locId,
    );

    final variants = await repo.variantsOf(productId);
    expect((await db.stockFor(variants.single.id)).available, 0);
    expect(await db.select(db.inventoryMovements).get(), isEmpty,
        reason: 'un cero no es un movimiento');
  });

  test('un cajero no puede dar de alta productos', () async {
    final actor = await admin();
    final catId = await repo.createCategory(actor, 'Gorras');
    final cashierId = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    final cashier = await (db.select(db.profiles)
          ..where((t) => t.id.equals(cashierId)))
        .getSingle();

    expect(
      () => repo.createSimpleProduct(cashier,
          name: 'X', categoryId: catId, basePriceCents: 100),
      throwsA(isA<Exception>()),
    );
  });
}
