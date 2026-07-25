import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/returns_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late SalesRepository sales;
  late ReturnsRepository returns;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
    returns = ReturnsRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<Variant> variant(int prodId, int locId, String sku,
      {int? override, int stock = 5}) async {
    final id = await db.into(db.variants).insert(VariantsCompanion.insert(
        productId: prodId,
        sku: sku,
        size: Value(sku),
        priceCentsOverride: Value(override)));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: id, locationId: locId, qty: stock, type: MovementType.receipt));
    return (db.select(db.variants)..where((t) => t.id.equals(id))).getSingle();
  }

  test(
      'Aceptación Fase 6: cambio talla M por G cobra la diferencia, stock correcto, '
      'y no se puede devolver dos veces la misma línea', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'Blusas'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Blusa', categoryId: catId, basePriceCents: 20000));
    final blusa =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final m = await variant(prodId, locId, 'M'); // 20000 (hereda)
    final g = await variant(prodId, locId, 'G', override: 25000);

    // Vende la M.
    final sale = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: blusa, variant: m, qty: 1, unitPriceCents: 20000)],
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
    );
    expect((await db.stockFor(m.id)).onHand, 4);

    final saleRow =
        await (db.select(db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final returnable = await returns.returnableLines(saleRow.id);
    expect(returnable.single.returnable, 1);

    // Cambia M por G (25000): diferencia 5000 en efectivo.
    final ex = await returns.processExchange(
      actor: caja,
      sale: saleRow,
      returnItems: [ReturnItem(returnable.single.line, 1)],
      newLines: [CheckoutLine(product: blusa, variant: g, qty: 1, unitPriceCents: 25000)],
      cashTenderedCents: 5000,
    );

    expect(ex.differenceCents, 5000);
    expect(ex.cashCollectedCents, 5000);
    expect(ex.changeCents, 0);

    // Inventario: M regresa a 5, G baja a 4.
    expect((await db.stockFor(m.id)).onHand, 5);
    expect((await db.stockFor(g.id)).onHand, 4);

    // La venta nueva quedó con crédito 20000 + efectivo 5000 = 25000.
    final newPayments = await (db.select(db.payments)
          ..where((t) => t.saleId.equals(ex.newSaleId)))
        .get();
    expect(newPayments.fold(0, (s, p) => s + p.amountCents), 25000);

    // Venta original marcada como devuelta.
    final updated =
        await (db.select(db.sales)..where((t) => t.id.equals(saleRow.id))).getSingle();
    expect(updated.status, SaleStatus.returned);

    // Devolver otra vez la MISMA línea original se rechaza (ya no hay devolvible).
    expect(
      returns.processReturn(
        actor: caja,
        sale: saleRow,
        items: [ReturnItem(returnable.single.line, 1)],
        method: RefundMethod.creditNote,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('devolución con nota de crédito regresa stock y crea la nota', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'P', categoryId: catId, basePriceCents: 10000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await variant(prodId, locId, 'U');

    final sale = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: v, qty: 2, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
    );
    final saleRow =
        await (db.select(db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final line = (await returns.returnableLines(saleRow.id)).single;

    final r = await returns.processReturn(
      actor: caja,
      sale: saleRow,
      items: [ReturnItem(line.line, 1)],
      method: RefundMethod.creditNote,
    );

    expect(r.refundCents, 10000);
    expect(r.creditNoteId, isNotNull);
    expect((await db.stockFor(v.id)).onHand, 4); // 5 - 2 vendidas + 1 devuelta
    final notes = await db.select(db.creditNotes).get();
    expect(notes.single.balanceCents, 10000);
    // Parcial: aún queda 1 por devolver.
    final updated =
        await (db.select(db.sales)..where((t) => t.id.equals(saleRow.id))).getSingle();
    expect(updated.status, SaleStatus.partialReturn);
  });

  test('reembolso en efectivo por un cajero sin autorización se rechaza',
      () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'P', categoryId: catId, basePriceCents: 10000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await variant(prodId, locId, 'U');
    final sale = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
    );
    final saleRow =
        await (db.select(db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final line = (await returns.returnableLines(saleRow.id)).single;

    expect(
      returns.processReturn(
          actor: caja,
          sale: saleRow,
          items: [ReturnItem(line.line, 1)],
          method: RefundMethod.cash),
      throwsA(anything),
    );
  });

  test('fuera del plazo de 15 días se rechaza', () async {
    final caja = await user(UserRole.cashier);
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final prodId = await db.into(db.products).insert(
        ProductsCompanion.insert(name: 'P', categoryId: catId, basePriceCents: 10000));
    final prod =
        await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await variant(prodId, locId, 'U');
    final sale = await sales.checkout(
      cashier: caja,
      locationId: locId,
      lines: [CheckoutLine(product: prod, variant: v, qty: 1, unitPriceCents: 10000)],
      payments: const [PaymentInput(PaymentMethod.cash, 10000)],
    );
    // Envejece la venta 20 días.
    await (db.update(db.sales)..where((t) => t.id.equals(sale.saleId))).write(
        SalesCompanion(
            createdAt: Value(DateTime.now().subtract(const Duration(days: 20)))));
    final saleRow =
        await (db.select(db.sales)..where((t) => t.id.equals(sale.saleId))).getSingle();
    final line = (await returns.returnableLines(saleRow.id)).single;

    expect(
      returns.processReturn(
          actor: caja,
          sale: saleRow,
          items: [ReturnItem(line.line, 1)],
          method: RefundMethod.creditNote),
      throwsA(isA<StateError>()),
    );
  });
}
