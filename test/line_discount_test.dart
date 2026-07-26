import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
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

  Future<(Product, Variant)> item(int locId, String sku, int price) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: sku, categoryId: catId, basePriceCents: price));
    final vid = await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: pid, sku: sku));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: vid, locationId: locId, qty: 50, type: MovementType.receipt));
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  test('descuento por línea reduce el total y se guarda en la línea', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (pa, va) = await item(locId, 'A', 10000);
    final (pb, vb) = await item(locId, 'B', 5000);

    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(
            product: pa, variant: va, qty: 2, unitPriceCents: 10000,
            lineDiscountCents: 5000), // 20000 - 5000 = 15000
        CheckoutLine(product: pb, variant: vb, qty: 1, unitPriceCents: 5000),
      ],
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
    );

    expect(r.grossCents, 25000);
    expect(r.totalCents, 20000); // 15000 + 5000
    expect(r.discountCents, 5000);

    final lines = await (db.select(db.saleLines)
          ..where((t) => t.saleId.equals(r.saleId)))
        .get();
    final la = lines.firstWhere((l) => l.variantId == va.id);
    final lb = lines.firstWhere((l) => l.variantId == vb.id);
    expect(la.discountCents, 5000);
    expect(la.lineTotalCents, 15000);
    expect(lb.discountCents, 0);
    expect(lb.lineTotalCents, 5000);
  });

  test('descuento por línea + por venta se combinan y cuadran al centavo', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (pa, va) = await item(locId, 'A', 10000);
    final (pb, vb) = await item(locId, 'B', 5000);

    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(
            product: pa, variant: va, qty: 2, unitPriceCents: 10000,
            lineDiscountCents: 5000), // base 15000
        CheckoutLine(product: pb, variant: vb, qty: 1, unitPriceCents: 5000), // base 5000
      ],
      discountCents: 2000, // sobre base 20000 -> net 18000
      payments: const [PaymentInput(PaymentMethod.cash, 18000)],
    );

    expect(r.totalCents, 18000);
    expect(r.discountCents, 25000 - 18000); // 7000

    final lines = await (db.select(db.saleLines)
          ..where((t) => t.saleId.equals(r.saleId)))
        .get();
    final sumLineTotals = lines.fold<int>(0, (s, l) => s + l.lineTotalCents);
    expect(sumLineTotals, 18000); // cuadra al centavo
  });
}
