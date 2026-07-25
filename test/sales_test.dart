import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';
import 'package:pos_boutique/features/sales/ticket_service.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<(Product, Variant)> stockedVariant(
    int locId, {
    required String sku,
    int price = 10000,
    int stock = 5,
  }) async {
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'C$sku'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Prod $sku', categoryId: catId, basePriceCents: price));
    final varId = await db
        .into(db.variants)
        .insert(VariantsCompanion.insert(productId: prodId, sku: sku));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: varId, locationId: locId, qty: stock, type: MovementType.receipt));
    final product =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final variant =
        await (db.select(db.variants)..where((t) => t.id.equals(varId))).getSingle();
    return (product, variant);
  }

  test(
      'Aceptación Fase 4: venta de 3 piezas baja el stock 1 c/u y registra todo',
      () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

    final a = await stockedVariant(locId, sku: 'A', price: 10000);
    final b = await stockedVariant(locId, sku: 'B', price: 25000);
    final c = await stockedVariant(locId, sku: 'C', price: 15000);

    final result = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 10000),
        CheckoutLine(product: b.$1, variant: b.$2, qty: 1, unitPriceCents: 25000),
        CheckoutLine(product: c.$1, variant: c.$2, qty: 1, unitPriceCents: 15000),
      ],
      payments: const [PaymentInput(PaymentMethod.cash, 60000)],
    );

    expect(result.totalCents, 50000);
    expect(result.changeCents, 10000);
    expect(result.folio, 'T1-000001');

    for (final v in [a.$2, b.$2, c.$2]) {
      final stock = await db.stockFor(v.id);
      expect(stock.onHand, 4, reason: 'SKU ${v.sku}');
    }

    expect(await db.select(db.sales).get(), hasLength(1));
    expect(await db.select(db.saleLines).get(), hasLength(3));
    expect(await db.select(db.payments).get(), hasLength(1));
  });

  test('pago dividido: mitad tarjeta / mitad efectivo suma al total', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await stockedVariant(locId, sku: 'A', price: 50000);

    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 50000)],
      payments: const [
        PaymentInput(PaymentMethod.card, 25000),
        PaymentInput(PaymentMethod.cash, 25000),
      ],
    );

    expect(r.totalCents, 50000);
    expect(r.changeCents, 0);
    final payments = await db.select(db.payments).get();
    expect(payments, hasLength(2));
    expect(payments.fold(0, (s, p) => s + p.amountCents), 50000);
  });

  test('descuento por venta: total neto, guarda descuento y audita', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await stockedVariant(locId, sku: 'A', price: 100000);

    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 100000)],
      payments: const [PaymentInput(PaymentMethod.cash, 90000)],
      discountCents: 10000,
      discountReason: 'Cliente frecuente',
    );

    expect(r.grossCents, 100000);
    expect(r.discountCents, 10000);
    expect(r.totalCents, 90000);
    expect(r.changeCents, 0);

    final sale =
        await (db.select(db.sales)..where((t) => t.id.equals(r.saleId))).getSingle();
    expect(sale.discountCents, 10000);
    expect(sale.subtotalCents + sale.taxCents, 90000);
    final audits = await (db.select(db.auditLog)
          ..where((t) => t.action.equals('sale_discount')))
        .get();
    expect(audits, hasLength(1));
  });

  test('cancelar venta: regresa stock, marca cancelled y audita', () async {
    final caja = await user(UserRole.cashier);
    final gerente = await user(UserRole.manager);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await stockedVariant(locId, sku: 'A', price: 10000, stock: 5);

    final r = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 2, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
    );
    expect((await db.stockFor(a.$2.id)).onHand, 3); // 5 - 2

    // Un cajero NO puede cancelar.
    await expectLater(
      sales.cancelSale(actor: caja, saleId: r.saleId),
      throwsA(isA<PermissionException>()),
    );

    // El gerente sí; el stock regresa a 5.
    await sales.cancelSale(actor: gerente, saleId: r.saleId, reason: 'prueba');
    expect((await db.stockFor(a.$2.id)).onHand, 5);

    final sale =
        await (db.select(db.sales)..where((t) => t.id.equals(r.saleId))).getSingle();
    expect(sale.status, SaleStatus.cancelled);
    final audits = await (db.select(db.auditLog)
          ..where((t) => t.action.equals('cancel_sale')))
        .get();
    expect(audits, hasLength(1));
  });

  test('el ticket PDF se genera (normal y de regalo)', () async {
    final data = TicketData(
      folio: 'T1-000001',
      dateTime: DateTime(2026, 7, 25, 12, 0),
      cashierName: 'Caja',
      lines: const [
        TicketLine(
            description: 'Blusa M Rosa',
            qty: 2,
            unitPriceCents: 24900,
            lineTotalCents: 49800),
      ],
      subtotalCents: 49800,
      discountCents: 0,
      taxCents: 6869,
      totalCents: 49800,
      payments: const [('Efectivo', 50000)],
      changeCents: 200,
      gift: false,
    );
    expect((await TicketService.buildPdf(data)).lengthInBytes, greaterThan(0));

    final gift = TicketData(
      folio: 'T1-000002',
      dateTime: DateTime(2026, 7, 25, 12, 5),
      cashierName: 'Caja',
      lines: data.lines,
      subtotalCents: 0,
      discountCents: 0,
      taxCents: 0,
      totalCents: 49800,
      payments: const [('Tarjeta', 49800)],
      changeCents: 0,
      gift: true,
    );
    expect((await TicketService.buildPdf(gift)).lengthInBytes, greaterThan(0));
  });
}
