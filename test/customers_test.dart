import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/customer_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late CustomerRepository customers;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    customers = CustomerRepository(db);
  });
  tearDown(() => db.close());

  Future<(Profile, int, Product, Variant)> fixtures() async {
    final loc =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final cashierId = await db.into(db.profiles).insert(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    final cashier =
        await (db.select(db.profiles)..where((t) => t.id.equals(cashierId)))
            .getSingle();
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Blusa', categoryId: catId, basePriceCents: 10000));
    final product =
        await (db.select(db.products)..where((t) => t.id.equals(prodId)))
            .getSingle();
    final varId = await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: prodId, sku: 'SKU1'));
    final variant =
        await (db.select(db.variants)..where((t) => t.id.equals(varId)))
            .getSingle();
    return (cashier, loc, product, variant);
  }

  test('crear y editar cliente', () async {
    final id = await customers.create(name: 'Ana López', phone: '5551234567');
    var c = await customers.byId(id);
    expect(c!.name, 'Ana López');
    expect(c.phone, '5551234567');

    await customers.update(id: id, name: 'Ana López', phone: '5550000000', email: 'ana@x.com');
    c = await customers.byId(id);
    expect(c!.phone, '5550000000');
    expect(c.email, 'ana@x.com');
  });

  test('búsqueda por nombre o teléfono', () async {
    await customers.create(name: 'Ana', phone: '55111');
    await customers.create(name: 'Beto', phone: '55222');
    expect((await customers.search('ana')).length, 1);
    expect((await customers.search('222')).single.name, 'Beto');
  });

  test('la venta asignada a un cliente aparece en su historial y totales',
      () async {
    final (cashier, loc, product, variant) = await fixtures();
    final custId = await customers.create(name: 'Cliente Fiel');

    final sales = SalesRepository(db);
    await sales.checkout(
      cashier: cashier,
      locationId: loc,
      lines: [
        CheckoutLine(
            product: product, variant: variant, qty: 2, unitPriceCents: 10000),
      ],
      payments: [const PaymentInput(PaymentMethod.cash, 20000)],
      customerId: custId,
    );

    final history = await customers.history(custId);
    expect(history, hasLength(1));
    expect(history.single.totalCents, 20000);

    final stats = await customers.stats(custId);
    expect(stats.visits, 1);
    expect(stats.spentCents, 20000);
    expect(stats.lastVisit, isNotNull);
  });

  test('cliente sin compras: totales en cero', () async {
    final id = await customers.create(name: 'Nuevo');
    final stats = await customers.stats(id);
    expect(stats.visits, 0);
    expect(stats.spentCents, 0);
    expect(stats.lastVisit, isNull);
  });

  test('una venta sin cliente no afecta a otros', () async {
    final (cashier, loc, product, variant) = await fixtures();
    final custId = await customers.create(name: 'Con historial');
    final sales = SalesRepository(db);
    // Venta sin cliente.
    await sales.checkout(
      cashier: cashier,
      locationId: loc,
      lines: [
        CheckoutLine(
            product: product, variant: variant, qty: 1, unitPriceCents: 10000),
      ],
      payments: [const PaymentInput(PaymentMethod.cash, 10000)],
    );
    final stats = await customers.stats(custId);
    expect(stats.visits, 0);
  });
}
