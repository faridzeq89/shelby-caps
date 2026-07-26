import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/reports_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late ReportsRepository reports;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
    reports = ReportsRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<Variant> variant(int prodId, int locId, String sku,
      {int stock = 20, int cost = 0}) async {
    final id = await db.into(db.variants).insert(VariantsCompanion.insert(
        productId: prodId, sku: sku, size: Value(sku), costCents: Value(cost)));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: id, locationId: locId, qty: stock, type: MovementType.receipt));
    return (db.select(db.variants)..where((t) => t.id.equals(id))).getSingle();
  }

  test(
      'Aceptación Fase 10: top vendidos y sin movimiento cuadran contra la suma '
      'de ventas del periodo', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Playera', categoryId: catId, basePriceCents: 10000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();

    final a = await variant(prodId, locId, 'A', cost: 4000); // se vende
    final b = await variant(prodId, locId, 'B', cost: 4000); // se vende menos
    final c = await variant(prodId, locId, 'C', cost: 4000); // NO se vende (muerto)

    // Vende 5 de A y 2 de B, en dos ventas.
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: a, qty: 5, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 50000)],
    );
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: b, qty: 2, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
    );

    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));

    // Resumen: 2 ventas, 7 piezas, $70000 netos.
    final summary = await reports.periodSummary(from, to);
    expect(summary.salesCount, 2);
    expect(summary.itemsSold, 7);
    expect(summary.netCents, 70000);

    // Top vendidos: A primero (5), luego B (2); C no aparece.
    final top = await reports.variantSales(from, to);
    expect(top.map((e) => e.sku).toList(), ['A', 'B']);
    expect(top.first.unitsSold, 5);

    // La suma de ingresos del top cuadra con las ventas netas del periodo.
    final topRevenue = top.fold<int>(0, (s, e) => s + e.revenueCents);
    expect(topRevenue, summary.netCents);

    // Inventario muerto (60 días): C nunca se vendió y tiene existencia.
    final dead = await reports.deadStock(days: 60);
    expect(dead.any((d) => d.sku == c.sku), isTrue);
    expect(dead.any((d) => d.sku == 'A'), isFalse);
  });

  test('margen usa el último costo y descuenta lo devuelto en unidades', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Pantalón', categoryId: catId, basePriceCents: 30000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await variant(prodId, locId, 'U', cost: 12000);

    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: v, qty: 3, unitPriceCents: 30000)],
      payments: const [PaymentInput(PaymentMethod.cash, 90000)],
    );

    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));
    final margins = await reports.marginByProduct(from, to);
    final m = margins.single;
    expect(m.unitsSold, 3);
    expect(m.revenueCents, 90000);
    expect(m.costCents, 36000); // 3 * 12000
    expect(m.marginCents, 54000);
  });

  test('ventas por vendedor cae al cajero cuando no hay vendedor', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P', categoryId: catId, basePriceCents: 10000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await variant(prodId, locId, 'U');
    await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
    );

    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));
    final bySeller = await reports.salesBySalesperson(from, to);
    expect(bySeller.single.name, caja.name);
    expect(bySeller.single.revenueCents, 10000);
  });
}
