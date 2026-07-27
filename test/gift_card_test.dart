import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/gift_card_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  late AppDatabase db;
  late GiftCardRepository cards;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cards = GiftCardRepository(db);
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

  Future<(Product, Variant)> item(int locId, int price) async {
    final catId =
        await db.into(db.categories).insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Prod', categoryId: catId, basePriceCents: price));
    final vid = await db.into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: 'V1'));
    await db.into(db.inventoryMovements).insert(InventoryMovementsCompanion.insert(
        variantId: vid, locationId: locId, qty: 20, type: MovementType.receipt));
    final p = await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v = await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  test('emite tarjeta con código único y saldo inicial', () async {
    final c = await cards.issue(initialCents: 50000);
    expect(c.code.startsWith('GR'), isTrue);
    expect(await cards.balance(c.id), 50000);
    final found = await cards.findByCode(c.code);
    expect(found, isNotNull);
    expect(found!.balanceCents, 50000);
  });

  test('canje reduce el saldo; sin saldo suficiente lanza', () async {
    final c = await cards.issue(initialCents: 50000);
    await cards.redeem(cardId: c.id, amountCents: 20000);
    expect(await cards.balance(c.id), 30000);
    expect(() => cards.redeem(cardId: c.id, amountCents: 40000),
        throwsA(isA<ArgumentError>()));
  });

  test('vender tarjeta crea venta con pago (entra al corte) y la tarjeta', () async {
    final caja = await cashier();
    final loc = await location();
    final res = await sales.sellGiftCard(
      cashier: caja,
      locationId: loc,
      amountCents: 50000,
      payments: const [PaymentInput(PaymentMethod.cash, 50000)],
    );
    expect(res.folio.isNotEmpty, isTrue);
    expect(await cards.balance(res.card.id), 50000);

    // Hay una venta con total 50000 y un pago en efectivo.
    final sale = await (db.select(db.sales)
          ..where((t) => t.folio.equals(res.folio)))
        .getSingle();
    expect(sale.totalCents, 50000);
    final pays = await (db.select(db.payments)
          ..where((t) => t.saleId.equals(sale.id)))
        .get();
    expect(pays.single.method, PaymentMethod.cash);
    expect(pays.single.amountCents, 50000);
  });

  test('pagar una venta con tarjeta de regalo debita el saldo', () async {
    final caja = await cashier();
    final loc = await location();
    final (p, v) = await item(loc, 30000); // $300
    final card = await cards.issue(initialCents: 50000);

    final r = await sales.checkout(
      cashier: caja,
      locationId: loc,
      lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 30000)],
      payments: [
        PaymentInput(PaymentMethod.giftCard, 20000, giftCardId: card.id),
        const PaymentInput(PaymentMethod.cash, 10000),
      ],
    );
    expect(r.totalCents, 30000);
    // La tarjeta bajó de 50000 a 30000.
    expect(await cards.balance(card.id), 30000);
    // Quedó registrado el pago con método giftCard.
    final pays = await (db.select(db.payments)
          ..where((t) => t.saleId.equals(r.saleId)))
        .get();
    expect(pays.any((x) => x.method == PaymentMethod.giftCard && x.amountCents == 20000),
        isTrue);
  });

  test('no deja pagar con tarjeta sin saldo suficiente (rollback)', () async {
    final caja = await cashier();
    final loc = await location();
    final (p, v) = await item(loc, 30000);
    final card = await cards.issue(initialCents: 5000); // solo $50

    expect(
      () => sales.checkout(
        cashier: caja,
        locationId: loc,
        lines: [CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 30000)],
        payments: [
          PaymentInput(PaymentMethod.giftCard, 20000, giftCardId: card.id),
          const PaymentInput(PaymentMethod.cash, 10000),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
    // Nada se aplicó: saldo intacto y sin venta.
    expect(await cards.balance(card.id), 5000);
    expect(await db.select(db.sales).get(), isEmpty);
  });

  test('ajuste manual suma y resta saldo', () async {
    final c = await cards.issue(initialCents: 10000);
    await cards.adjust(c.id, 5000);
    await cards.adjust(c.id, -2000);
    expect(await cards.balance(c.id), 13000);
  });
}
