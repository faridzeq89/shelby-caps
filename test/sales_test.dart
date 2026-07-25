import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Crea una variante con stock inicial y devuelve (product, variant).
  Future<(Product, Variant)> stockedVariant(
    Profile admin,
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
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

    final a = await stockedVariant(caja, locId, sku: 'A', price: 10000);
    final b = await stockedVariant(caja, locId, sku: 'B', price: 25000);
    final c = await stockedVariant(caja, locId, sku: 'C', price: 15000);

    final result = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [
        CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 10000),
        CheckoutLine(product: b.$1, variant: b.$2, qty: 1, unitPriceCents: 25000),
        CheckoutLine(product: c.$1, variant: c.$2, qty: 1, unitPriceCents: 15000),
      ],
      method: PaymentMethod.cash,
      amountTenderedCents: 60000,
    );

    // Total y cambio.
    expect(result.totalCents, 50000);
    expect(result.changeCents, 10000);
    expect(result.folio, 'T1-000001');

    // Cada variante bajó exactamente 1 (de 5 a 4).
    for (final v in [a.$2, b.$2, c.$2]) {
      final stock = await db.stockFor(v.id);
      expect(stock.onHand, 4, reason: 'SKU ${v.sku}');
    }

    // Persistencia: 1 venta, 3 líneas, 1 pago.
    expect(await db.select(db.sales).get(), hasLength(1));
    expect(await db.select(db.saleLines).get(), hasLength(3));
    expect(await db.select(db.payments).get(), hasLength(1));

    final sale =
        await (db.select(db.sales)..where((t) => t.id.equals(result.saleId)))
            .getSingle();
    expect(sale.status, SaleStatus.completed);
    // IVA incluido: subtotal + tax = total.
    expect(sale.subtotalCents + sale.taxCents, sale.totalCents);
  });

  test('los folios avanzan entre ventas', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await stockedVariant(caja, locId, sku: 'X');

    final r1 = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 10000)],
      method: PaymentMethod.cash,
      amountTenderedCents: 10000,
    );
    final r2 = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 10000)],
      method: PaymentMethod.cash,
      amountTenderedCents: 10000,
    );
    expect(r1.folio, 'T1-000001');
    expect(r2.folio, 'T1-000002');
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
      subtotalCents: 42931,
      taxCents: 6869,
      totalCents: 49800,
      tenderedCents: 50000,
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
      taxCents: 0,
      totalCents: 49800,
      tenderedCents: 49800,
      changeCents: 0,
      gift: true,
    );
    expect((await TicketService.buildPdf(gift)).lengthInBytes, greaterThan(0));
  });
}
