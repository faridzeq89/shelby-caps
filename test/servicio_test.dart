import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/quote_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<(Product, Variant)> item(int locId, String sku, int price,
      {bool servicio = false, int stock = 0}) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: sku,
        categoryId: catId,
        basePriceCents: price,
        esServicio: Value(servicio)));
    final vid = await db
        .into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: sku));
    if (stock > 0) {
      await db.into(db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
              variantId: vid,
              locationId: locId,
              qty: stock,
              type: MovementType.receipt));
    }
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  test('el servicio se vende pero NO descuenta inventario; el producto normal sí',
      () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (prodNormal, vNormal) = await item(locId, 'GORRA', 15000, stock: 10);
    final (servicio, vServ) = await item(locId, 'LIMPIEZA', 0, servicio: true);

    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(product: prodNormal, variant: vNormal, qty: 2, unitPriceCents: 15000),
        // Servicio con precio ya definido (como quedaría tras la cotización).
        CheckoutLine(product: servicio, variant: vServ, qty: 1, unitPriceCents: 20000),
      ],
      payments: const [PaymentInput(PaymentMethod.cash, 50000)],
    );

    // El producto normal bajó de 10 a 8.
    expect((await db.stockFor(vNormal.id)).available, 8);
    // El servicio no tiene movimientos de inventario (sigue en 0, sin negativos).
    expect((await db.stockFor(vServ.id)).available, 0);
    final movs = await (db.select(db.inventoryMovements)
          ..where((t) => t.variantId.equals(vServ.id)))
        .get();
    expect(movs, isEmpty);
  });

  test('editar el precio de un renglón de cotización recalcula el total', () async {
    final quotes = QuoteRepository(db);
    final actorId = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Jefe', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    final actor =
        await (db.select(db.profiles)..where((t) => t.id.equals(actorId))).getSingle();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (_, vServ) = await item(locId, 'LIMPIEZA', 0, servicio: true);

    // Cotización con el servicio sin precio (0).
    final q = await quotes.create(actor: actor, lines: [
      QuoteDraftLine(variantId: vServ.id, qty: 1, unitPriceCents: 0),
    ]);
    expect(q.totalCents, 0);

    final line = (await quotes.linesOf(q.id)).single;
    await quotes.updateLinePrice(actor, line.id, 18000);

    final updated =
        await (db.select(db.quotes)..where((t) => t.id.equals(q.id))).getSingle();
    expect(updated.totalCents, 18000);
    expect((await quotes.linesOf(q.id)).single.lineTotalCents, 18000);
  });
}
