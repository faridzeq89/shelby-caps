import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  group('wholesalePriceFor (resolución de mayoreo)', () {
    PriceTier tier(int minQty, int priceCents) => PriceTier(
        id: minQty, productId: 1, minQty: minQty, priceCents: priceCents,
        createdAt: DateTime(2026));

    test('sin escalones o por debajo del umbral: precio normal (null)', () {
      expect(wholesalePriceFor(const [], 100), isNull);
      expect(wholesalePriceFor([tier(10, 15000)], 9), isNull);
    });

    test('al alcanzar el umbral aplica el escalón', () {
      expect(wholesalePriceFor([tier(10, 15000)], 10), 15000);
      expect(wholesalePriceFor([tier(10, 15000)], 25), 15000);
    });

    test('escalonado: toma el mayor umbral alcanzado (orden indistinto)', () {
      final tiers = [tier(50, 12000), tier(10, 15000)];
      expect(wholesalePriceFor(tiers, 9), isNull);
      expect(wholesalePriceFor(tiers, 10), 15000);
      expect(wholesalePriceFor(tiers, 49), 15000);
      expect(wholesalePriceFor(tiers, 50), 12000);
    });
  });

  group('CatalogRepository.setPriceTiers', () {
    late AppDatabase db;
    late CatalogRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = CatalogRepository(db);
    });
    tearDown(() => db.close());

    Future<Profile> admin() async {
      final id = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Jefe', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
      return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
    }

    Future<int> product() async {
      final catId = await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(name: 'Gorras'));
      return db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Shelby', categoryId: catId, basePriceCents: 20000));
    }

    test('guarda, ordena, deduplica y quita escalones', () async {
      final actor = await admin();
      final pid = await product();

      await repo.setPriceTiers(actor: actor, productId: pid, tiers: [
        (minQty: 50, priceCents: 12000),
        (minQty: 10, priceCents: 15000),
        (minQty: 10, priceCents: 14000), // duplicado: gana el último
        (minQty: 1, priceCents: 9999), // inválido: minQty<=1
      ]);

      var tiers = await repo.priceTiersOf(pid);
      expect(tiers.map((t) => t.minQty).toList(), [10, 50]); // ordenado
      expect(tiers.firstWhere((t) => t.minQty == 10).priceCents, 14000);

      // Reemplazo total: lista vacía quita el mayoreo.
      await repo.setPriceTiers(actor: actor, productId: pid, tiers: []);
      tiers = await repo.priceTiersOf(pid);
      expect(tiers, isEmpty);
    });

    test('el cajero no puede editar escalones', () async {
      final pid = await product();
      final cid = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
      final caja =
          await (db.select(db.profiles)..where((t) => t.id.equals(cid))).getSingle();
      expect(
        () => repo.setPriceTiers(
            actor: caja, productId: pid, tiers: [(minQty: 10, priceCents: 15000)]),
        throwsA(isA<PermissionException>()),
      );
    });
  });

  group('venta con precio de mayoreo', () {
    late AppDatabase db;
    late CatalogRepository catalog;
    late SalesRepository sales;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      catalog = CatalogRepository(db);
      sales = SalesRepository(db);
    });
    tearDown(() => db.close());

    test('cantidad surtida cruza el umbral y el precio de venta es el mayoreo',
        () async {
      final adminId = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Jefe', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
      final actor =
          await (db.select(db.profiles)..where((t) => t.id.equals(adminId))).getSingle();
      final locId =
          await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
      final catId = await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(name: 'Gorras'));
      final pid = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Shelby', categoryId: catId, basePriceCents: 20000));

      // Dos variantes (negra/blanca) del mismo modelo.
      final vNegra = await db.into(db.variants).insert(
          VariantsCompanion.insert(productId: pid, sku: 'SHELBY-NEG'));
      final vBlanca = await db.into(db.variants).insert(
          VariantsCompanion.insert(productId: pid, sku: 'SHELBY-BLA'));
      for (final vid in [vNegra, vBlanca]) {
        await db.into(db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: vid,
                locationId: locId,
                qty: 100,
                type: MovementType.receipt));
      }
      final pNegra =
          await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
      final varNegra = await (db.select(db.variants)
            ..where((t) => t.id.equals(vNegra)))
          .getSingle();
      final varBlanca = await (db.select(db.variants)
            ..where((t) => t.id.equals(vBlanca)))
          .getSingle();

      await catalog.setPriceTiers(
          actor: actor, productId: pid, tiers: [(minQty: 10, priceCents: 15000)]);

      // Carrito surtido: 6 negras + 6 blancas = 12 ≥ 10 → mayoreo para ambas.
      final tiers = await catalog.priceTiersOf(pid);
      final totalQty = 6 + 6;
      final unit = wholesalePriceFor(tiers, totalQty);
      expect(unit, 15000);

      final r = await sales.checkout(
        cashier: actor,
        locationId: locId,
        lines: [
          CheckoutLine(
              product: pNegra, variant: varNegra, qty: 6, unitPriceCents: unit!),
          CheckoutLine(
              product: pNegra, variant: varBlanca, qty: 6, unitPriceCents: unit),
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 180000)],
      );

      // 12 × 15000 = 180000 (no 12 × 20000 = 240000).
      expect(r.grossCents, 180000);
      expect(r.totalCents, 180000);
    });
  });
}
