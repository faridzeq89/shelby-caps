import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/services/catalog_sync_service.dart';

/// Lo que el dueño pidió el 20 ago 2026, en sus palabras: poder **eliminar**
/// categorías creadas por error, que las archivadas **dejen de aparecer**, y
/// poder **elegir el orden a mano** en la tienda web ("no solo por filtros de
/// nuevo, a-z").
///
/// Hasta hoy las categorías solo se podían crear, de paso, al dar de alta un
/// producto: no había pantalla, ni orden, ni forma de quitarlas.
void main() {
  late AppDatabase db;
  late CatalogRepository catalogo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    catalogo = CatalogRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> producto(int catId, String nombre) =>
      db.into(db.products).insert(ProductsCompanion.insert(
          name: nombre, categoryId: catId, basePriceCents: 45000));

  group('alta y nombre', () {
    test('cada categoría nueva se va al final del orden', () async {
      final admin = await user(UserRole.admin);
      await catalogo.createCategory(admin, 'NEW ERA');
      await catalogo.createCategory(admin, 'ORIGINALES');
      await catalogo.createCategory(admin, 'LIMPIEZA');
      final cats = await catalogo.categories();
      expect([for (final c in cats) c.name],
          ['NEW ERA', 'ORIGINALES', 'LIMPIEZA']);
      expect([for (final c in cats) c.sortOrder], [0, 1, 2]);
    });

    test('borrar una y crear otra no empata el orden', () async {
      // Con el conteo de filas (lo que se usaba antes) la tercera nacía con el
      // mismo sort_order que otra y el orden quedaba a la suerte.
      final admin = await user(UserRole.admin);
      final a = await catalogo.createCategory(admin, 'A');
      await catalogo.createCategory(admin, 'B');
      await catalogo.deleteCategory(admin, a);
      await catalogo.createCategory(admin, 'C');
      final cats = await catalogo.categories();
      final ordenes = [for (final c in cats) c.sortOrder];
      expect(ordenes.toSet().length, ordenes.length,
          reason: 'ninguna categoría comparte lugar');
    });

    test('sin nombre no se crea ni se renombra', () async {
      final admin = await user(UserRole.admin);
      expect(() => catalogo.createCategory(admin, '   '),
          throwsA(isA<StateError>()));
      final id = await catalogo.createCategory(admin, 'GORRAS');
      expect(() => catalogo.renameCategory(admin, id, ''),
          throwsA(isA<StateError>()));
    });

    test('renombrar recorta y queda en la bitácora', () async {
      final admin = await user(UserRole.admin);
      final id = await catalogo.createCategory(admin, 'GORRAS');
      await catalogo.renameCategory(admin, id, '  NEW ERA  ');
      final c = await (db.select(db.categories)..where((t) => t.id.equals(id)))
          .getSingle();
      expect(c.name, 'NEW ERA');
      final log = await (db.select(db.auditLog)
            ..where((t) => t.entityType.equals('category')))
          .get();
      expect(log.any((r) => r.action == 'rename'), isTrue);
    });

    test('el cajero no administra categorías', () async {
      final caja = await user(UserRole.cashier);
      expect(() => catalogo.createCategory(caja, 'X'),
          throwsA(isA<PermissionException>()));
    });
  });

  group('archivadas: dejan de aparecer', () {
    test('salen de la lista que se ofrece, no de la que etiqueta', () async {
      final admin = await user(UserRole.admin);
      final gorras = await catalogo.createCategory(admin, 'GORRAS');
      final vieja = await catalogo.createCategory(admin, 'TEMPORADA VIEJA');
      await catalogo.setCategoryActive(admin, vieja, false);

      // Para escoger y para filtrar: solo las vivas. Esto es lo que arregla
      // "las categorías archivadas siguen apareciendo en el catálogo".
      expect([
        for (final c in await catalogo.categories(activeOnly: true)) c.id
      ], [gorras]);
      // Para etiquetar: todas, porque un producto puede seguir ahí.
      expect((await catalogo.categories()).length, 2);
    });

    test('archivar no toca sus productos', () async {
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'GORRAS');
      final pid = await producto(cat, 'Gorra negra');
      await catalogo.setCategoryActive(admin, cat, false);
      final p = await (db.select(db.products)..where((t) => t.id.equals(pid)))
          .getSingle();
      expect(p.active, isTrue, reason: 'la mercancía sigue a la venta');
    });

    test('se reactiva y vuelve', () async {
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'GORRAS');
      await catalogo.setCategoryActive(admin, cat, false);
      await catalogo.setCategoryActive(admin, cat, true);
      expect((await catalogo.categories(activeOnly: true)).length, 1);
    });
  });

  group('eliminar', () {
    test('una categoría vacía se borra de verdad', () async {
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'CREADA POR ERROR');
      expect(await catalogo.categoryHasProducts(cat), isFalse);
      await catalogo.deleteCategory(admin, cat);
      expect(await db.select(db.categories).get(), isEmpty);
    });

    test('con productos se ARCHIVA en vez de borrarse, y no se los lleva',
        () async {
      // `category_id` es obligatorio: borrarla dejaría productos huérfanos. La
      // app lo dice en el diálogo y archiva.
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'GORRAS');
      await producto(cat, 'Gorra negra');
      expect(await catalogo.categoryHasProducts(cat), isTrue);
      await catalogo.deleteCategory(admin, cat);
      expect((await db.select(db.products).get()).length, 1);
      final quedo = await (db.select(db.categories)
            ..where((t) => t.id.equals(cat)))
          .getSingle();
      expect(quedo.active, isFalse, reason: 'se archivó, no se borró');
    });

    test('cuenta también los productos archivados', () async {
      // Un producto archivado sigue colgando de su categoría: si se borrara la
      // categoría, quedaría apuntando a una que no existe.
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'GORRAS');
      final pid = await producto(cat, 'Gorra negra');
      await catalogo.setProductActive(admin, pid, false);
      expect(await catalogo.categoryHasProducts(cat), isTrue);
      expect((await catalogo.categoryProductCounts())[cat], 1);
    });
  });

  group('orden a mano', () {
    test('reordenar reescribe el orden completo', () async {
      final admin = await user(UserRole.admin);
      final a = await catalogo.createCategory(admin, 'LIMPIEZA');
      final b = await catalogo.createCategory(admin, 'NEW ERA');
      final c = await catalogo.createCategory(admin, 'ORIGINALES');

      // Lo que más vende, primero — no lo que empieza con "L".
      await catalogo.reorderCategories(admin, [b, c, a]);

      expect([for (final x in await catalogo.categories()) x.name],
          ['NEW ERA', 'ORIGINALES', 'LIMPIEZA']);
    });

    test('el cajero no reordena', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final a = await catalogo.createCategory(admin, 'A');
      expect(() => catalogo.reorderCategories(caja, [a]),
          throwsA(isA<PermissionException>()));
    });
  });

  group('lo que llega a la tienda', () {
    test('las categorías viajan con su lugar y su bandera', () async {
      final admin = await user(UserRole.admin);
      final limpieza = await catalogo.createCategory(admin, 'LIMPIEZA');
      final newEra = await catalogo.createCategory(admin, 'NEW ERA');
      final vieja = await catalogo.createCategory(admin, 'TEMPORADA VIEJA');
      await catalogo.setCategoryActive(admin, vieja, false);
      await catalogo.reorderCategories(admin, [newEra, limpieza, vieja]);

      final cats = await catalogo.categories();
      final snap = CatalogSyncService.buildSnapshot(
        products: const [],
        categoryNames: {for (final c in cats) c.id: c.name},
        variants: const [],
        tiers: const [],
        categories: cats,
      );

      expect([for (final c in snap.categories) c['name']],
          ['NEW ERA', 'LIMPIEZA', 'TEMPORADA VIEJA']);
      expect([for (final c in snap.categories) c['position']], [0, 1, 2]);
      // La archivada viaja marcada, no ausente: si no viajara, la tienda no
      // podría distinguirla de una categoría publicada por un POS más viejo y
      // la volvería a mostrar.
      expect(snap.categories.last['active'], isFalse);
      expect(snap.categories.first['active'], isTrue);
    });

    test('un producto en categoría archivada conserva su etiqueta', () async {
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'TEMPORADA VIEJA');
      final pid = await producto(cat, 'Gorra vieja');
      await catalogo.setCategoryActive(admin, cat, false);

      final cats = await catalogo.categories();
      final p = await (db.select(db.products)..where((t) => t.id.equals(pid)))
          .getSingle();
      final snap = CatalogSyncService.buildSnapshot(
        products: [p],
        categoryNames: {for (final c in cats) c.id: c.name},
        variants: const [],
        tiers: const [],
        categories: cats,
      );
      expect(snap.products.single['category'], 'TEMPORADA VIEJA');
    });
  });

  group('lo que ve el mostrador', () {
    test('el filtro por categoría sigue trayendo sus productos', () async {
      final admin = await user(UserRole.admin);
      final cat = await catalogo.createCategory(admin, 'GORRAS');
      await db.into(db.products).insert(ProductsCompanion.insert(
          name: 'Gorra negra',
          categoryId: cat,
          basePriceCents: 45000,
          brand: const Value('JC HATS')));
      final lista = await catalogo.productsByCategory(cat);
      expect(lista.single.name, 'Gorra negra');
    });
  });
}
