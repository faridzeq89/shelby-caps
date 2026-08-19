import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/inventory_repository.dart';

/// Lo que el dueño pidió el 19 ago 2026: poder corregir el **nombre** y las
/// **existencias** desde la pantalla del producto, sin ir a Inventario.
///
/// Lo que se prueba aquí no es la pantalla, es la regla que la sostiene: el
/// nombre se puede cambiar sin perder el producto, y la existencia se corrige
/// **asentando un movimiento**, nunca sobrescribiendo un número. Si alguien
/// algún día "simplifica" eso a un UPDATE, estas pruebas truenan.
void main() {
  late AppDatabase db;
  late CatalogRepository catalogo;
  late InventoryRepository inv;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    catalogo = CatalogRepository(db);
    inv = InventoryRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'Principal'));

  Future<int> producto(String nombre) async {
    final cat = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'Gorras'));
    return db.into(db.products).insert(ProductsCompanion.insert(
        name: nombre, categoryId: cat, basePriceCents: 45000));
  }

  Future<Variant> variante(int prodId, int locId, {int stock = 0}) async {
    final id = await db.into(db.variants).insert(
        VariantsCompanion.insert(productId: prodId, sku: 'U', size: const Value('U')));
    if (stock != 0) {
      await db.into(db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
              variantId: id,
              locationId: locId,
              qty: stock,
              type: MovementType.receipt));
    }
    return (db.select(db.variants)..where((t) => t.id.equals(id))).getSingle();
  }

  group('nombre del producto', () {
    test('se puede corregir sin volver a dar de alta el producto', () async {
      final admin = await user(UserRole.admin);
      final id = await producto('Gorra Negrs');

      await catalogo.updateProductName(
          actor: admin, productId: id, newName: 'Gorra Negra');

      expect((await catalogo.productById(id))!.name, 'Gorra Negra');
    });

    test('se guarda recortado', () async {
      final admin = await user(UserRole.admin);
      final id = await producto('x');
      await catalogo.updateProductName(
          actor: admin, productId: id, newName: '  Gorra NY  ');
      expect((await catalogo.productById(id))!.name, 'Gorra NY');
    });

    test('no puede quedar vacío: un producto sin nombre no se puede vender',
        () async {
      final admin = await user(UserRole.admin);
      final id = await producto('Gorra NY');
      await expectLater(
        catalogo.updateProductName(actor: admin, productId: id, newName: '   '),
        throwsArgumentError,
      );
      expect((await catalogo.productById(id))!.name, 'Gorra NY',
          reason: 'el nombre viejo se conserva');
    });

    test('el cajero no renombra el catálogo', () async {
      final cajero = await user(UserRole.cashier);
      final id = await producto('Gorra NY');
      await expectLater(
        catalogo.updateProductName(
            actor: cajero, productId: id, newName: 'Otra'),
        throwsA(isA<PermissionException>()),
      );
    });

    test('queda registrado quién lo cambió', () async {
      final admin = await user(UserRole.admin);
      final id = await producto('Gorra NY');
      await catalogo.updateProductName(
          actor: admin, productId: id, newName: 'Gorra LA');

      final log = await (db.select(db.auditLog)
            ..where((t) => t.action.equals('update_name')))
          .getSingle();
      expect(log.userId, admin.id);
      expect(log.detail, contains('Gorra LA'));
    });
  });

  group('marca y descripción (lo que ve la tienda web)', () {
    test('se pueden escribir: antes se publicaban y no había dónde llenarlas',
        () async {
      final admin = await user(UserRole.admin);
      final id = await producto('Gorra NY');

      await catalogo.updateProductPresentation(
          actor: admin,
          productId: id,
          brand: 'New Era',
          description: '59FIFTY, cerrada, talla única');

      final p = (await catalogo.productById(id))!;
      expect(p.brand, 'New Era');
      expect(p.description, '59FIFTY, cerrada, talla única');
    });

    test('vacío se guarda como nulo, no como cadena vacía', () async {
      final admin = await user(UserRole.admin);
      final id = await producto('Gorra NY');
      await catalogo.updateProductPresentation(
          actor: admin, productId: id, brand: 'New Era', description: 'algo');

      await catalogo.updateProductPresentation(
          actor: admin, productId: id, brand: '  ', description: '');

      final p = (await catalogo.productById(id))!;
      expect(p.brand, isNull);
      expect(p.description, isNull,
          reason: 'la tienda esconde el bloque con nulo; "" lo dejaría vacío');
    });

    test('el cajero no las toca', () async {
      final cajero = await user(UserRole.cashier);
      final id = await producto('Gorra NY');
      await expectLater(
        catalogo.updateProductPresentation(
            actor: cajero, productId: id, brand: 'X'),
        throwsA(isA<PermissionException>()),
      );
    });
  });

  group('existencias desde el producto', () {
    test('escribir "tengo 12" cuando hay 5 asienta un ajuste de +7', () async {
      final admin = await user(UserRole.admin);
      final loc = await location();
      final v = await variante(await producto('Gorra NY'), loc, stock: 5);

      // Es lo que hace la pantalla: la diferencia, no el número.
      const objetivo = 12;
      final actual = (await db.stockFor(v.id)).onHand;
      await inv.adjust(admin,
          variantId: v.id,
          locationId: loc,
          qty: objetivo - actual,
          reason: AdjustmentReason.correction);

      expect((await db.stockFor(v.id)).onHand, 12);

      final movs = await (db.select(db.inventoryMovements)
            ..where((t) => t.variantId.equals(v.id)))
          .get();
      expect(movs.length, 2, reason: 'la recepción original y el ajuste');
      final ajuste = movs.firstWhere((m) => m.type == MovementType.adjustment);
      expect(ajuste.qty, 7);
      expect(ajuste.reason, contains('Corrección'));
    });

    test('bajar la existencia deja el movimiento negativo, no borra historia',
        () async {
      final admin = await user(UserRole.admin);
      final loc = await location();
      final v = await variante(await producto('Gorra LA'), loc, stock: 10);

      await inv.adjust(admin,
          variantId: v.id,
          locationId: loc,
          qty: 3 - 10,
          reason: AdjustmentReason.loss,
          note: 'se mojaron');

      expect((await db.stockFor(v.id)).onHand, 3);
      final movs = await (db.select(db.inventoryMovements)
            ..where((t) => t.variantId.equals(v.id)))
          .get();
      expect(movs.length, 2, reason: 'el ledger solo crece');
      final ajuste = movs.firstWhere((m) => m.type == MovementType.adjustment);
      expect(ajuste.qty, -7);
      expect(ajuste.reason, contains('se mojaron'));
    });

    test('el cajero no puede ajustar existencias sin autorización', () async {
      final cajero = await user(UserRole.cashier);
      final loc = await location();
      final v = await variante(await producto('Gorra NY'), loc, stock: 5);

      await expectLater(
        inv.adjust(cajero,
            variantId: v.id,
            locationId: loc,
            qty: 5,
            reason: AdjustmentReason.correction),
        throwsA(isA<PermissionException>()),
      );
      expect((await db.stockFor(v.id)).onHand, 5);
    });
  });
}
