import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/cash_session_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late CashSessionRepository cash;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
    cash = CashSessionRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<(Product, Variant)> variant(int locId, String sku) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C$sku'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P$sku', categoryId: catId, basePriceCents: 10000));
    final varId =
        await db.into(db.variants).insert(VariantsCompanion.insert(productId: prodId, sku: sku));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: varId, locationId: locId, qty: 50, type: MovementType.receipt));
    final p = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(varId))).getSingle();
    return (p, v);
  }

  test(
      'Aceptación Fase 5: abrir \$500, 5 ventas (una dividida), el esperado cuadra',
      () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final item = await variant(locId, 'A');

    await cash.open(actor: caja, locationId: locId, openingFloatCents: 50000);
    final session = (await cash.currentOpen(locId))!;

    // 4 ventas de $100 en efectivo.
    for (var i = 0; i < 4; i++) {
      await sales.checkout(
        cashier: caja,
        locationId: locId,
        lines: [
          CheckoutLine(product: item.$1, variant: item.$2, qty: 1, unitPriceCents: 10000)
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 10000)],
      );
    }
    // 1 venta de $100 mitad tarjeta / mitad efectivo.
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(product: item.$1, variant: item.$2, qty: 1, unitPriceCents: 10000)
      ],
      payments: const [
        PaymentInput(PaymentMethod.card, 5000),
        PaymentInput(PaymentMethod.cash, 5000),
      ],
    );

    final sum = await cash.summary(session);
    // Efectivo de ventas: 4*100 + 50 = 450. Tarjeta: 50.
    expect(sum.cashSalesCents, 45000);
    expect(sum.cardSalesCents, 5000);
    // Esperado en cajón = fondo 500 + efectivo 450 = 950.
    expect(sum.expectedCashCents, 95000);

    // Un retiro de $100 baja el esperado a $850.
    await cash.recordCash(
        actor: caja,
        session: session,
        kind: CashMovementKind.withdrawal,
        amountCents: 10000);
    final sum2 = await cash.summary(session);
    expect(sum2.expectedCashCents, 85000);

    // Cierre contando $850 exactos: sin diferencia.
    final closed = await cash.close(actor: caja, session: session, countedCents: 85000);
    expect(closed.expectedCents, 85000);
    expect(closed.varianceCents, 0);
    expect(closed.status, CashSessionStatus.closed);
  });

  test('no deja abrir dos cajas a la vez', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    await cash.open(actor: caja, locationId: locId, openingFloatCents: 0);
    await expectLater(
      cash.open(actor: caja, locationId: locId, openingFloatCents: 0),
      throwsA(isA<StateError>()),
    );
  });
}
