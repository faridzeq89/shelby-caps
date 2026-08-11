import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/quote_repository.dart';

void main() {
  late AppDatabase db;
  late QuoteRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = QuoteRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> actor() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> variant(String sku) async {
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: sku, categoryId: catId, basePriceCents: 10000));
    return db.into(db.variants).insert(
        VariantsCompanion.insert(productId: pid, sku: sku));
  }

  test('crea cotización con folio, totales y renglones', () async {
    final a = await actor();
    final v1 = await variant('A');
    final v2 = await variant('B');

    final q = await repo.create(actor: a, lines: [
      QuoteDraftLine(variantId: v1, qty: 2, unitPriceCents: 10000), // 20000
      QuoteDraftLine(
          variantId: v2, qty: 1, unitPriceCents: 5000, lineDiscountCents: 1000),
    ], validDays: 15, notes: 'Para Juan');

    expect(q.folio, startsWith('COT-'));
    expect(q.status, QuoteStatus.open);
    expect(q.subtotalCents, 25000); // 20000 + 5000
    expect(q.totalCents, 24000); // − 1000 de descuento
    expect(q.expiresAt, isNotNull);
    expect(q.notes, 'Para Juan');

    final lines = await repo.linesOf(q.id);
    expect(lines, hasLength(2));
    expect(lines.firstWhere((l) => l.variantId == v2).lineTotalCents, 4000);

    expect(await repo.open(), hasLength(1));
  });

  test('cancelar saca la cotización de las vigentes', () async {
    final a = await actor();
    final v1 = await variant('A');
    final q = await repo.create(
        actor: a, lines: [QuoteDraftLine(variantId: v1, qty: 1, unitPriceCents: 10000)]);
    await repo.cancel(a, q.id);
    expect(await repo.open(), isEmpty);
    expect(await repo.all(), hasLength(1));
  });

  test('markConverted liga la venta y marca converted', () async {
    final a = await actor();
    final v1 = await variant('A');
    final q = await repo.create(
        actor: a, lines: [QuoteDraftLine(variantId: v1, qty: 1, unitPriceCents: 10000)]);
    await repo.markConverted(q.id, 'sale-uuid-123');
    final updated =
        await (db.select(db.quotes)..where((t) => t.id.equals(q.id))).getSingle();
    expect(updated.status, QuoteStatus.converted);
    expect(updated.convertedSaleId, 'sale-uuid-123');
    expect(await repo.open(), isEmpty);
  });

  test('rechaza cotización sin renglones', () async {
    final a = await actor();
    expect(() => repo.create(actor: a, lines: const []),
        throwsA(isA<ArgumentError>()));
  });
}
