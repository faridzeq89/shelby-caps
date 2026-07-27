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
  late int locId;
  late int catId;
  late Profile caja;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
    reports = ReportsRepository(db);
    locId = await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    catId = await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    caja = await (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  });
  tearDown(() => db.close());

  Future<(Product, Variant)> variant(String sku,
      {int price = 10000, int stock = 0}) async {
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: sku, categoryId: catId, basePriceCents: price));
    final vid = await db.into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: sku));
    if (stock > 0) {
      await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
          variantId: vid, locationId: locId, qty: stock, type: MovementType.receipt));
    }
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  Future<void> sell(Product p, Variant v, int qty, {DateTime? at}) async {
    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: p, variant: v, qty: qty, unitPriceCents: 10000)],
      payments: [PaymentInput(PaymentMethod.cash, 10000 * qty)],
    );
    if (at != null) {
      await (db.update(db.sales)..where((t) => t.id.equals(r.saleId)))
          .write(SalesCompanion(createdAt: Value(at)));
    }
  }

  test('recomienda REABASTECER lo que se vende rápido y queda poco', () async {
    final (p, v) = await variant('RAPIDO', stock: 10);
    await sell(p, v, 8); // vendió 8 recientes, quedan 2
    final recs = await reports.recommendations();
    final rec = recs.firstWhere((r) => r.sku == 'RAPIDO');
    expect(rec.kind, RecoKind.restock);
    expect(rec.action, 'Reabastecer');
  });

  test('recomienda PONER EN OFERTA lo que tiene stock y no se vende hace mucho',
      () async {
    final (p, v) = await variant('ESTANCADO', stock: 5);
    // una venta hace 60 días
    await sell(p, v, 1, at: DateTime.now().subtract(const Duration(days: 60)));
    final recs = await reports.recommendations();
    final rec = recs.firstWhere((r) => r.sku == 'ESTANCADO');
    expect(rec.kind, RecoKind.promo);
    expect(rec.action, 'Poner en oferta');
  });

  test('recomienda DESCUENTO al sobre-stock de venta lenta', () async {
    final (p, v) = await variant('LENTO', stock: 20);
    await sell(p, v, 1); // 1 venta reciente, mucho stock
    final recs = await reports.recommendations();
    final rec = recs.firstWhere((r) => r.sku == 'LENTO');
    expect(rec.kind, RecoKind.overstock);
    expect(rec.action, 'Considerar descuento');
  });

  test('menos vendidos ordena de menor a mayor', () async {
    final (pa, va) = await variant('A', stock: 50);
    final (pb, vb) = await variant('B', stock: 50);
    await sell(pa, va, 10); // A se vende mucho
    await sell(pb, vb, 1); //  B se vende poco
    final from = DateTime.now().subtract(const Duration(days: 1));
    final to = DateTime.now().add(const Duration(days: 1));
    final asc = await reports.variantSales(from, to, ascending: true);
    expect(asc.first.sku, 'B'); // el que menos vendió va primero
  });
}
