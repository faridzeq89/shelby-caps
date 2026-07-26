import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/reconciliation_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late ReconciliationRepository recon;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recon = ReconciliationRepository(db);
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<(Product, Variant)> item(int locId, {int stock = 0}) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Prod', categoryId: catId, basePriceCents: 10000));
    final vid = await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: pid, sku: 'SKU${DateTime.now().microsecondsSinceEpoch}'));
    if (stock != 0) {
      await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
          variantId: vid, locationId: locId, qty: stock, type: MovementType.receipt));
    }
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  ReconGroup group(List<ReconGroup> gs, String name) =>
      gs.firstWhere((g) => g.name == name);

  test('sin problemas cuando todo cuadra', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (p, v) = await item(locId, stock: 5);
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
    );
    expect(await recon.issueCount(), 0);
  });

  test('detecta stock negativo (la pieza en la mano gana)', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final (p, v) = await item(locId, stock: 1);
    // Vende 3 aunque solo hay 1 -> on_hand queda -2.
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: p, variant: v, qty: 3, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 30000)],
    );
    final groups = await recon.run();
    expect(group(groups, 'Stock negativo').issues.length, 1);
  });

  test('detecta pagos que no cuadran', () async {
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final caja = await cashier();
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: 's1',
          folio: 'T1-000009',
          locationId: locId,
          cashierId: caja.id,
          status: SaleStatus.completed,
          subtotalCents: 10000,
          taxCents: 0,
          totalCents: 10000,
        ));
    await db.into(db.payments).insert(PaymentsCompanion.insert(
        saleId: 's1', method: PaymentMethod.cash, amountCents: 5000, cashierId: caja.id));
    final groups = await recon.run();
    expect(group(groups, 'Pagos que no cuadran').issues.length, 1);
  });
}
