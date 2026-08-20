import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/quote_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

/// Lo que el dueño reportó el 20 ago 2026: pidió poder **eliminar** productos
/// creados por error y la app solo dejaba archivar.
///
/// La causa: borrar exigía cero movimientos de inventario, y un producto nace
/// con un `receipt` (su existencia inicial). Nacía imborrable.
///
/// La regla nueva y la línea que estas pruebas cuidan: **se borra lo que nunca
/// se vendió**. Si hay una venta, no se borra ni con permiso de admin — ahí hay
/// tickets y cortes de caja apuntando a esa fila. Y el candado del ledger tiene
/// que quedar puesto otra vez al terminar: si alguien "simplifica" la puerta y
/// la deja abierta, la última prueba truena.
void main() {
  late AppDatabase db;
  late CatalogRepository catalogo;
  late SalesRepository ventas;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    catalogo = CatalogRepository(db);
    ventas = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'Principal'));

  /// Una gorra como la captura el dueño: producto, variante y su existencia
  /// inicial (que es justo lo que antes lo volvía imborrable).
  Future<(Product, Variant)> gorra(int locId,
      {String nombre = 'Gorra', int stock = 12}) async {
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'Gorras'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: nombre, categoryId: catId, basePriceCents: 45000));
    final vid = await db
        .into(db.variants)
        .insert(VariantsCompanion.insert(productId: pid, sku: 'SKU-$nombre'));
    await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
            variantId: vid,
            locationId: locId,
            qty: stock,
            type: MovementType.receipt));
    final p =
        await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v =
        await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  group('alta por error', () {
    test('se borra aunque tenga existencia inicial (el caso del cliente)',
        () async {
      final admin = await user(UserRole.admin);
      final locId = await location();
      final (p, v) = await gorra(locId);

      expect(await catalogo.productHasMovements(p.id), isTrue,
          reason: 'su existencia inicial ya dejó un movimiento');
      expect(await catalogo.canDeleteProduct(p.id), isTrue,
          reason: 'nunca se vendió: se puede borrar');

      await catalogo.deleteProduct(admin, p.id);

      expect(
          await (db.select(db.products)..where((t) => t.id.equals(p.id)))
              .getSingleOrNull(),
          isNull);
      expect(
          await (db.select(db.variants)..where((t) => t.id.equals(v.id)))
              .getSingleOrNull(),
          isNull);
      final movs = await (db.select(db.inventoryMovements)
            ..where((t) => t.variantId.equals(v.id)))
          .get();
      expect(movs, isEmpty,
          reason: 'los movimientos del producto se van con él');
    });

    test('se lleva códigos, fotos y escalones de mayoreo', () async {
      final admin = await user(UserRole.admin);
      final locId = await location();
      final (p, v) = await gorra(locId);
      await db.into(db.barcodes).insert(BarcodesCompanion.insert(
          variantId: v.id, code: 'MB0000000001', source: BarcodeSource.internal));
      await db.into(db.productImages).insert(
          ProductImagesCompanion.insert(productId: p.id, path: '/tmp/foto.jpg'));
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          productId: p.id, minQty: 10, priceCents: 40000));

      await catalogo.deleteProduct(admin, p.id);

      expect(await db.select(db.barcodes).get(), isEmpty);
      expect(await db.select(db.productImages).get(), isEmpty);
      expect(await db.select(db.priceTiers).get(), isEmpty);
    });

    test('en una cotización entregada NO se borra', () async {
      // La cotización es un papel que ya se le dio a un cliente: si el producto
      // desaparece, esa nota queda apuntando a nada.
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, nombre: 'Cotizada');
      await QuoteRepository(db).create(
        actor: caja,
        lines: [QuoteDraftLine(variantId: v.id, qty: 1, unitPriceCents: 45000)],
      );
      expect(await catalogo.canDeleteProduct(p.id), isFalse);
      await expectLater(
          catalogo.deleteProduct(admin, p.id), throwsA(isA<StateError>()));
    });

    test('el cajero no borra el catálogo', () async {
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, _) = await gorra(locId);
      expect(() => catalogo.deleteProduct(caja, p.id),
          throwsA(isA<PermissionException>()));
    });
  });

  group('lo que ya se vendió', () {
    Future<Product> vendida(Profile caja, int locId) async {
      final (p, v) = await gorra(locId, nombre: 'Vendida');
      await ventas.checkout(
        cashier: caja,
        locationId: locId,
        lines: [
          CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 45000)
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 45000)],
      );
      return p;
    }

    test('no se puede borrar: se archiva', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final p = await vendida(caja, locId);

      expect(await catalogo.productHasSales(p.id), isTrue);
      expect(await catalogo.canDeleteProduct(p.id), isFalse);
      await expectLater(
          catalogo.deleteProduct(admin, p.id), throwsA(isA<StateError>()));

      // Sigue completo: la venta no puede quedar apuntando a nada.
      expect(
          await (db.select(db.products)..where((t) => t.id.equals(p.id)))
              .getSingleOrNull(),
          isNotNull);

      await catalogo.setProductActive(admin, p.id, false);
      final archivado = await (db.select(db.products)
            ..where((t) => t.id.equals(p.id)))
          .getSingle();
      expect(archivado.active, isFalse);
    });

    test('el intento fallido no se lleva sus movimientos', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final p = await vendida(caja, locId);
      final antes = (await db.select(db.inventoryMovements).get()).length;

      await expectLater(
          catalogo.deleteProduct(admin, p.id), throwsA(isA<StateError>()));

      expect((await db.select(db.inventoryMovements).get()).length, antes);
    });
  });

  group('el candado del ledger', () {
    test('sigue puesto después de un borrado', () async {
      final admin = await user(UserRole.admin);
      final locId = await location();
      final (p1, _) = await gorra(locId, nombre: 'Una');
      final (_, v2) = await gorra(locId, nombre: 'Otra');

      await catalogo.deleteProduct(admin, p1.id);

      // La puerta se abre SOLO dentro de deleteProduct. Aquí afuera, borrar un
      // movimiento a mano tiene que seguir siendo imposible.
      await expectLater(
        (db.delete(db.inventoryMovements)
              ..where((t) => t.variantId.equals(v2.id)))
            .go(),
        throwsA(anything),
      );
      expect(
          (await (db.select(db.inventoryMovements)
                    ..where((t) => t.variantId.equals(v2.id)))
                  .get())
              .length,
          1);
    });

    test('sigue puesto aunque el borrado falle', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, nombre: 'Vendida');
      await ventas.checkout(
        cashier: caja,
        locationId: locId,
        lines: [
          CheckoutLine(product: p, variant: v, qty: 1, unitPriceCents: 45000)
        ],
        payments: const [PaymentInput(PaymentMethod.cash, 45000)],
      );
      await expectLater(
          catalogo.deleteProduct(admin, p.id), throwsA(isA<StateError>()));

      await expectLater(
        (db.delete(db.inventoryMovements)
              ..where((t) => t.variantId.equals(v.id)))
            .go(),
        throwsA(anything),
      );
    });

    test('el UPDATE nunca se permite, ni durante un borrado', () async {
      final locId = await location();
      final (_, v) = await gorra(locId);
      await expectLater(
        (db.update(db.inventoryMovements)
              ..where((t) => t.variantId.equals(v.id)))
            .write(const InventoryMovementsCompanion(qty: Value(999))),
        throwsA(anything),
      );
    });
  });
}
