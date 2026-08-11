import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';

/// Galería de fotos por producto. Lo delicado aquí es que la **portada** vive
/// en `products.imagePath` y el resto en `product_images`: al cambiar de
/// portada se intercambian, y ninguna foto debe perderse en el camino.
void main() {
  late AppDatabase db;
  late CatalogRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CatalogRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> admin() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Admin', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> gorra(Profile actor) async {
    final catId = await repo.createCategory(actor, 'Gorras');
    return repo.createProduct(actor,
        name: 'ALO NEGRA', categoryId: catId, basePriceCents: 85000);
  }

  test('la primera foto se vuelve la portada', () async {
    final actor = await admin();
    final id = await gorra(actor);

    await repo.addProductImage(actor: actor, productId: id, path: '/f/frente.jpg');

    final p = await repo.productById(id);
    expect(p!.imagePath, '/f/frente.jpg');
    expect(await repo.galleryOf(id), isEmpty,
        reason: 'la portada no se duplica en la galería');
  });

  test('las siguientes fotos se acomodan en la galería, en orden', () async {
    final actor = await admin();
    final id = await gorra(actor);

    for (final f in ['frente', 'perfil', 'atras', 'detalle']) {
      await repo.addProductImage(actor: actor, productId: id, path: '/f/$f.jpg');
    }

    expect(await repo.allImagesOf(id), [
      '/f/frente.jpg',
      '/f/perfil.jpg',
      '/f/atras.jpg',
      '/f/detalle.jpg',
    ]);
  });

  test('hacer portada intercambia, no pierde la anterior', () async {
    final actor = await admin();
    final id = await gorra(actor);
    await repo.addProductImage(actor: actor, productId: id, path: '/f/frente.jpg');
    await repo.addProductImage(actor: actor, productId: id, path: '/f/perfil.jpg');

    final perfil = (await repo.galleryOf(id)).single;
    await repo.setMainImage(actor: actor, productId: id, imageId: perfil.id);

    final p = await repo.productById(id);
    expect(p!.imagePath, '/f/perfil.jpg', reason: 'la elegida sube a portada');
    expect((await repo.galleryOf(id)).single.path, '/f/frente.jpg',
        reason: 'la portada anterior baja a la galería en vez de borrarse');
    expect((await repo.allImagesOf(id)).length, 2);
  });

  test('quitar una foto devuelve su ruta para borrar el archivo', () async {
    final actor = await admin();
    final id = await gorra(actor);
    await repo.addProductImage(actor: actor, productId: id, path: '/f/frente.jpg');
    await repo.addProductImage(actor: actor, productId: id, path: '/f/perfil.jpg');

    final perfil = (await repo.galleryOf(id)).single;
    final path = await repo.removeGalleryImage(actor: actor, imageId: perfil.id);

    expect(path, '/f/perfil.jpg');
    expect(await repo.allImagesOf(id), ['/f/frente.jpg']);
  });

  test('un cajero no puede tocar las fotos', () async {
    final actor = await admin();
    final id = await gorra(actor);
    final cashierId = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    final cashier = await (db.select(db.profiles)
          ..where((t) => t.id.equals(cashierId)))
        .getSingle();

    expect(
      () => repo.addProductImage(
          actor: cashier, productId: id, path: '/f/x.jpg'),
      throwsA(isA<Exception>()),
    );
  });
}
