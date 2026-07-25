import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/layaway_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late LayawayRepository layaway;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    layaway = LayawayRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<(Product, Variant)> item(int locId, String sku, int price) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C$sku'));
    final prodId = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'P$sku', categoryId: catId, basePriceCents: price));
    final varId =
        await db.into(db.variants).insert(VariantsCompanion.insert(productId: prodId, sku: sku));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: varId, locationId: locId, qty: 5, type: MovementType.receipt));
    final p = await (db.select(db.products)..where((t) => t.id.equals(prodId))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(varId))).getSingle();
    return (p, v);
  }

  test(
      'Aceptación Fase 7: apartado 2 piezas 30%, reserva sin tocar on_hand, '
      'dos abonos, liquidación con 3 pagos', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await item(locId, 'A', 50000);
    final b = await item(locId, 'B', 50000);
    final custId = await layaway.createCustomer('Ana', '555');

    final created = await layaway.createLayaway(
      actor: caja,
      locationId: locId,
      customerId: custId,
      lines: [
        CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 50000),
        CheckoutLine(product: b.$1, variant: b.$2, qty: 1, unitPriceCents: 50000),
      ],
      depositCents: 30000, // 30% de 100000
    );
    expect(created.totalCents, 100000);
    expect(created.depositRequiredCents, 30000);
    expect(created.balanceCents, 70000);

    // Reservado: on_hand sigue en 5, pero available baja a 4.
    for (final v in [a.$2, b.$2]) {
      final s = await db.stockFor(v.id);
      expect(s.onHand, 5, reason: v.sku);
      expect(s.reserved, 1, reason: v.sku);
      expect(s.available, 4, reason: v.sku);
    }

    // Dos abonos liquidan el saldo.
    expect(await layaway.addPayment(actor: caja, saleId: created.saleId, amountCents: 40000), 30000);
    expect(await layaway.addPayment(actor: caja, saleId: created.saleId, amountCents: 30000), 0);

    // Liquidar: sale de existencia y libera la reserva.
    await layaway.settle(actor: caja, saleId: created.saleId);
    for (final v in [a.$2, b.$2]) {
      final s = await db.stockFor(v.id);
      expect(s.onHand, 4, reason: v.sku); // 5 - 1 vendida
      expect(s.reserved, 0, reason: v.sku);
    }

    final sale = await (db.select(db.sales)..where((t) => t.id.equals(created.saleId))).getSingle();
    expect(sale.status, SaleStatus.completed);
    expect(await layaway.paymentsOf(created.saleId), hasLength(3)); // anticipo + 2 abonos
  });

  test('anticipo menor al 30% se rechaza', () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await item(locId, 'A', 50000);
    final custId = await layaway.createCustomer('Ana', null);
    expect(
      layaway.createLayaway(
        actor: caja,
        locationId: locId,
        customerId: custId,
        lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 50000)],
        depositCents: 10000, // 20%, menor al 30%
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('vencimiento libera la reserva y crea nota de crédito por lo pagado',
      () async {
    final caja = await cashier();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final a = await item(locId, 'A', 50000);
    final custId = await layaway.createCustomer('Ana', null);
    final created = await layaway.createLayaway(
      actor: caja,
      locationId: locId,
      customerId: custId,
      lines: [CheckoutLine(product: a.$1, variant: a.$2, qty: 1, unitPriceCents: 50000)],
      depositCents: 15000,
      dueDate: DateTime.now().subtract(const Duration(days: 1)), // ya vencido
    );
    expect((await db.stockFor(a.$2.id)).available, 4); // reservado

    final n = await layaway.expireOverdue(actor: caja);
    expect(n, 1);
    expect((await db.stockFor(a.$2.id)).available, 5); // liberado
    final notes = await db.select(db.creditNotes).get();
    expect(notes.single.balanceCents, 15000); // lo pagado a favor
    final terms = await (db.select(db.layawayTerms)
          ..where((t) => t.saleId.equals(created.saleId)))
        .getSingle();
    expect(terms.status, LayawayStatus.expired);
  });
}
