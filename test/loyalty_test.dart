import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/loyalty_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late LoyaltyRepository loyalty;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
    loyalty = LoyaltyRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> customer() =>
      db.into(db.customers).insert(CustomersCompanion.insert(name: 'Ana'));

  Future<(Product, Variant, int)> setup() async {
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Vestido', categoryId: catId, basePriceCents: 10000));
    final vid = await db.into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: 'V1'));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: vid, locationId: locId, qty: 20, type: MovementType.receipt));
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v, locId);
  }

  test('gana puntos en la venta (1 punto por peso por defecto)', () async {
    final caja = await cashier();
    final cid = await customer();
    final (p, v, loc) = await setup();
    final r = await sales.checkout(
      cashier: caja,
      locationId: loc,
      lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
      customerId: cid,
    );
    expect(r.earnedPoints, 100); // $100 → 100 pts
    expect(await loyalty.balance(cid), 100);
  });

  test('canjea puntos como descuento y baja el saldo', () async {
    final caja = await cashier();
    final cid = await customer();
    final (p, v, loc) = await setup();
    await loyalty.adjust(cid, 50); // saldo inicial 50 pts

    final r = await sales.checkout(
      cashier: caja,
      locationId: loc,
      lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 9500)],
      customerId: cid,
      redeemPoints: 50, // 50 * 10c = $5 de descuento
    );
    expect(r.redeemedPoints, 50);
    expect(r.totalCents, 9500); // 10000 - 500
    expect(r.earnedPoints, 95); // gana sobre el neto pagado
    // 50 inicial - 50 canjeados + 95 ganados = 95
    expect(await loyalty.balance(cid), 95);
  });

  test('no deja canjear más puntos de los que tiene', () async {
    final caja = await cashier();
    final cid = await customer();
    final (p, v, loc) = await setup();
    await loyalty.adjust(cid, 10);
    expect(
      () => sales.checkout(
        cashier: caja,
        locationId: loc,
        lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
        payments: const [PaymentInput(PaymentMethod.cash, 10000)],
        customerId: cid,
        redeemPoints: 50,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('canjear sin cliente lanza error', () async {
    final caja = await cashier();
    final (p, v, loc) = await setup();
    expect(
      () => sales.checkout(
        cashier: caja,
        locationId: loc,
        lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
        payments: const [PaymentInput(PaymentMethod.cash, 10000)],
        redeemPoints: 10,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('setConfig cambia las reglas de ganar y canjear', () async {
    await loyalty.setConfig(earnPerPeso: 2, redeemCentsPerPoint: 5);
    final cfg = await loyalty.config();
    expect(cfg.earnPerPeso, 2);
    expect(cfg.redeemCentsPerPoint, 5);

    final caja = await cashier();
    final cid = await customer();
    final (p, v, loc) = await setup();
    final r = await sales.checkout(
      cashier: caja,
      locationId: loc,
      lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
      customerId: cid,
    );
    expect(r.earnedPoints, 200); // 2 pts por peso
  });

  test('ajuste manual suma y resta puntos', () async {
    final cid = await customer();
    await loyalty.adjust(cid, 80);
    await loyalty.adjust(cid, -30);
    expect(await loyalty.balance(cid), 50);
    final h = await loyalty.history(cid);
    expect(h.every((t) => t.type == LoyaltyType.adjust), isTrue);
  });
}
