import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

void main() {
  group('wholesaleActive (mayoreo por total de carrito)', () {
    test('se activa al alcanzar el umbral, no antes', () {
      expect(wholesaleActive(9, 10), isFalse);
      expect(wholesaleActive(10, 10), isTrue);
      expect(wholesaleActive(25, 10), isTrue);
    });

    test('umbral <= 0 apaga el mayoreo', () {
      expect(wholesaleActive(100, 0), isFalse);
    });
  });

  group('CatalogRepository.setWholesalePrice', () {
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

    Future<Product> productRow(int pid) =>
        (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();

    test('guarda el precio de mayoreo y luego lo quita con null', () async {
      final actor = await admin();
      final pid = await product();

      await repo.setWholesalePrice(
          actor: actor, productId: pid, priceCents: 15000);
      expect((await productRow(pid)).wholesalePriceCents, 15000);

      await repo.setWholesalePrice(
          actor: actor, productId: pid, priceCents: null);
      expect((await productRow(pid)).wholesalePriceCents, isNull);
    });

    test('rechaza un mayoreo que no sea menor al menudeo', () async {
      final actor = await admin();
      final pid = await product();
      // Igual al menudeo: inválido.
      expect(
        () => repo.setWholesalePrice(
            actor: actor, productId: pid, priceCents: 20000),
        throwsA(isA<ArgumentError>()),
      );
      // Mayor al menudeo: inválido.
      expect(
        () => repo.setWholesalePrice(
            actor: actor, productId: pid, priceCents: 25000),
        throwsA(isA<ArgumentError>()),
      );
      // No debió guardar nada.
      expect((await productRow(pid)).wholesalePriceCents, isNull);
    });

    test('el cajero no puede editar el mayoreo', () async {
      final pid = await product();
      final cid = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
      final caja = await (db.select(db.profiles)..where((t) => t.id.equals(cid)))
          .getSingle();
      expect(
        () => repo.setWholesalePrice(
            actor: caja, productId: pid, priceCents: 15000),
        throwsA(isA<PermissionException>()),
      );
    });
  });

  group('CatalogRepository umbral global', () {
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

    test('sin configurar cae al default (10) y luego persiste el cambio',
        () async {
      expect(await repo.wholesaleThreshold(), wholesaleThresholdFallback);
      final actor = await admin();
      await repo.setWholesaleThreshold(actor, 6);
      expect(await repo.wholesaleThreshold(), 6);
    });

    test('un umbral menor a 1 se rechaza', () async {
      final actor = await admin();
      expect(() => repo.setWholesaleThreshold(actor, 0),
          throwsA(isA<ArgumentError>()));
    });

    test('el cajero no puede cambiar el umbral', () async {
      final cid = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
      final caja = await (db.select(db.profiles)..where((t) => t.id.equals(cid)))
          .getSingle();
      expect(() => repo.setWholesaleThreshold(caja, 5),
          throwsA(isA<PermissionException>()));
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

    test('el total del carrito (varios modelos) cruza el umbral y aplica mayoreo',
        () async {
      final adminId = await db.insertProfile(ProfilesCompanion.insert(
          name: 'Jefe', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
      final actor = await (db.select(db.profiles)
            ..where((t) => t.id.equals(adminId)))
          .getSingle();
      final locId =
          await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
      final catId = await db
          .into(db.categories)
          .insert(CategoriesCompanion.insert(name: 'Gorras'));

      // Dos modelos DISTINTOS, cada uno con su propio precio de mayoreo.
      final pidA = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Modelo A', categoryId: catId, basePriceCents: 20000));
      final pidB = await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Modelo B', categoryId: catId, basePriceCents: 30000));
      await catalog.setWholesalePrice(
          actor: actor, productId: pidA, priceCents: 15000);
      await catalog.setWholesalePrice(
          actor: actor, productId: pidB, priceCents: 24000);

      final vA = await db.into(db.variants).insert(
          VariantsCompanion.insert(productId: pidA, sku: 'A-1'));
      final vB = await db.into(db.variants).insert(
          VariantsCompanion.insert(productId: pidB, sku: 'B-1'));
      for (final vid in [vA, vB]) {
        await db.into(db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: vid,
                locationId: locId,
                qty: 100,
                type: MovementType.receipt));
      }
      final prodA =
          await (db.select(db.products)..where((t) => t.id.equals(pidA))).getSingle();
      final prodB =
          await (db.select(db.products)..where((t) => t.id.equals(pidB))).getSingle();
      final varA =
          await (db.select(db.variants)..where((t) => t.id.equals(vA))).getSingle();
      final varB =
          await (db.select(db.variants)..where((t) => t.id.equals(vB))).getSingle();

      // 6 del modelo A + 6 del modelo B = 12 ≥ 10 → mayoreo para AMBOS aunque
      // ninguno por sí solo llegue a 10 (antes no habría aplicado).
      final threshold = await catalog.wholesaleThreshold();
      final totalQty = 6 + 6;
      expect(wholesaleActive(totalQty, threshold), isTrue);

      final r = await sales.checkout(
        cashier: actor,
        locationId: locId,
        lines: [
          CheckoutLine(
              product: prodA,
              variant: varA,
              qty: 6,
              unitPriceCents: prodA.wholesalePriceCents!),
          CheckoutLine(
              product: prodB,
              variant: varB,
              qty: 6,
              unitPriceCents: prodB.wholesalePriceCents!),
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 234000)],
      );

      // 6×15000 + 6×24000 = 90000 + 144000 = 234000 (no el menudeo 300000).
      expect(r.grossCents, 234000);
      expect(r.totalCents, 234000);
    });
  });
}
