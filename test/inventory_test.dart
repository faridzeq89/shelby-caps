import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/inventory_repository.dart';

void main() {
  late AppDatabase db;
  late InventoryRepository inv;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    inv = InventoryRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

  Future<int> category() =>
      db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Blusas'));

  Future<Variant> variant(int prodId, int locId, String sku,
      {int stock = 0, int? minStock}) async {
    final id = await db.into(db.variants).insert(VariantsCompanion.insert(
        productId: prodId,
        sku: sku,
        size: Value(sku),
        minStock: Value(minStock)));
    if (stock != 0) {
      await db.into(db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
              variantId: id, locationId: locId, qty: stock, type: MovementType.receipt));
    }
    return (db.select(db.variants)..where((t) => t.id.equals(id))).getSingle();
  }

  test(
      'Aceptación Fase 9: conteo con diferencia de 2 piezas se ajusta con motivo '
      'y deja rastro en el ledger', () async {
    final admin = await user(UserRole.admin);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Blusa', categoryId: cat, basePriceCents: 20000));
    // Sistema cree que hay 10; físicamente hay 8 (faltan 2).
    final v = await variant(prodId, loc, 'M', stock: 10);
    expect((await db.stockFor(v.id)).onHand, 10);

    final countId = await inv.createCount(admin, locationId: loc);
    await inv.setCountLine(countId, v.id, 8);

    final lines = await inv.countLines(countId);
    expect(lines.single.line.systemQty, 10);
    expect(lines.single.line.countedQty, 8);
    expect(lines.single.difference, -2);

    final adjusted = await inv.applyCount(admin, countId);
    expect(adjusted, 1);

    // El stock del sistema quedó igual a lo contado.
    expect((await db.stockFor(v.id)).onHand, 8);

    // Rastro en el ledger: un movimiento `count` de -2.
    final counts = await (db.select(db.inventoryMovements)
          ..where((t) => t.type.equalsValue(MovementType.count)))
        .get();
    expect(counts.single.qty, -2);
    expect(counts.single.reason, contains('Conteo físico'));

    // La sesión quedó aplicada.
    final session =
        await (db.select(db.stockCounts)..where((t) => t.id.equals(countId))).getSingle();
    expect(session.status, StockCountStatus.applied);
  });

  test('recepción registra movimientos receipt y opcionalmente actualiza costo',
      () async {
    final admin = await user(UserRole.admin);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Pantalón', categoryId: cat, basePriceCents: 30000));
    final v = await variant(prodId, loc, 'M', stock: 0);

    await inv.receiveBatch(admin, locationId: loc, lines: [
      ReceiptLine(variantId: v.id, qty: 5, unitCostCents: 12000, updateCost: true),
    ]);

    expect((await db.stockFor(v.id)).onHand, 5);
    final updated =
        await (db.select(db.variants)..where((t) => t.id.equals(v.id))).getSingle();
    expect(updated.costCents, 12000);
  });

  test('un cajero no puede recibir ni ajustar', () async {
    final caja = await user(UserRole.cashier);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: cat, basePriceCents: 10000));
    final v = await variant(prodId, loc, 'U', stock: 3);

    expect(
      inv.receiveBatch(caja,
          locationId: loc, lines: [ReceiptLine(variantId: v.id, qty: 1)]),
      throwsA(isA<PermissionException>()),
    );
    expect(
      inv.adjust(caja,
          variantId: v.id,
          locationId: loc,
          qty: -1,
          reason: AdjustmentReason.loss),
      throwsA(isA<PermissionException>()),
    );
  });

  test('un cajero SÍ puede ajustar con autorización de gerente', () async {
    final caja = await user(UserRole.cashier);
    final gerente = await user(UserRole.manager);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: cat, basePriceCents: 10000));
    final v = await variant(prodId, loc, 'U', stock: 3);

    await inv.adjust(caja,
        variantId: v.id,
        locationId: loc,
        qty: -1,
        reason: AdjustmentReason.damaged,
        authorizedBy: gerente);
    expect((await db.stockFor(v.id)).onHand, 2);
  });

  test('el ajuste de cero piezas se rechaza', () async {
    final admin = await user(UserRole.admin);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: cat, basePriceCents: 10000));
    final v = await variant(prodId, loc, 'U', stock: 3);
    expect(
      inv.adjust(admin,
          variantId: v.id,
          locationId: loc,
          qty: 0,
          reason: AdjustmentReason.correction),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('stock bajo: respeta mínimo por variante y default global', () async {
    final admin = await user(UserRole.admin);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: cat, basePriceCents: 10000));

    // Default global = 3.
    await inv.setLowStockDefault(admin, 3);

    // A: 2 en stock, sin mínimo propio → bajo (2 <= 3).
    final a = await variant(prodId, loc, 'A', stock: 2);
    // B: 5 en stock, sin mínimo propio → ok (5 > 3).
    await variant(prodId, loc, 'B', stock: 5);
    // C: 4 en stock, mínimo propio 6 → bajo (4 <= 6).
    final c = await variant(prodId, loc, 'C', stock: 4, minStock: 6);
    // D: 1 en stock, mínimo propio 0 → alerta desactivada.
    await variant(prodId, loc, 'D', stock: 1, minStock: 0);

    final low = await inv.lowStockVariants();
    final ids = low.map((e) => e.variant.id).toSet();
    expect(ids, {a.id, c.id});
    expect(await inv.lowStockCount(), 2);
  });

  test('la reserva de un apartado cuenta como no disponible para la alerta',
      () async {
    final admin = await user(UserRole.admin);
    final loc = await location();
    final cat = await category();
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: cat, basePriceCents: 10000));
    await inv.setLowStockDefault(admin, 3);
    // 5 en on_hand, pero 3 reservadas → disponible 2 (<= 3) → bajo.
    final v = await variant(prodId, loc, 'U', stock: 5);
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: v.id, locationId: loc, qty: 3, type: MovementType.reserve));

    final low = await inv.lowStockVariants();
    expect(low.single.variant.id, v.id);
    expect(low.single.available, 2);
  });
}
