import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/banner_repository.dart';

/// Anuncios de la tienda. Lo que importa: que solo haya UNA portada, que el
/// orden se pueda cambiar, y que apagar no sea lo mismo que borrar.
void main() {
  late AppDatabase db;
  late BannerRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = BannerRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('los banners se agregan al final y conservan el orden', () async {
    final actor = await user(UserRole.admin);
    for (final n in ['uno', 'dos', 'tres']) {
      await repo.addBanner(actor, path: '/img/$n.jpg', caption: n);
    }
    expect((await repo.banners()).map((b) => b.caption), ['uno', 'dos', 'tres']);
  });

  test('mover intercambia con el vecino y respeta los extremos', () async {
    final actor = await user(UserRole.admin);
    for (final n in ['uno', 'dos', 'tres']) {
      await repo.addBanner(actor, path: '/img/$n.jpg', caption: n);
    }
    final list = await repo.banners();

    await repo.move(actor, list[2].id, -1); // "tres" sube
    expect((await repo.banners()).map((b) => b.caption), ['uno', 'tres', 'dos']);

    await repo.move(actor, list[0].id, -1); // el primero ya no puede subir
    expect((await repo.banners()).map((b) => b.caption), ['uno', 'tres', 'dos'],
        reason: 'mover fuera de rango no debe reordenar nada');
  });

  test('solo hay una portada, y cambiarla devuelve la anterior para borrarla',
      () async {
    final actor = await user(UserRole.admin);

    expect(await repo.setCover(actor, path: '/img/p1.jpg'), isNull,
        reason: 'no había portada previa');
    final vieja = await repo.setCover(actor, path: '/img/p2.jpg');

    expect(vieja, '/img/p1.jpg',
        reason: 'quien llama necesita la ruta para borrar el archivo');
    expect((await repo.cover())!.path, '/img/p2.jpg');
    final todas = await db.select(db.storeBanners).get();
    expect(todas.where((b) => b.isCover).length, 1,
        reason: 'nunca deben quedar dos portadas');
  });

  test('apagar un banner lo saca de la tienda pero no lo borra', () async {
    final actor = await user(UserRole.admin);
    await repo.addBanner(actor, path: '/img/a.jpg', caption: 'a');
    await repo.addBanner(actor, path: '/img/b.jpg', caption: 'b');
    final list = await repo.banners();

    await repo.setActive(actor, list.first.id, false);

    expect((await repo.banners()).length, 2, reason: 'sigue en la lista');
    expect((await repo.published()).map((b) => b.caption), ['b'],
        reason: 'pero no se publica');
  });

  test('la portada va primero en lo que se publica', () async {
    final actor = await user(UserRole.admin);
    await repo.addBanner(actor, path: '/img/a.jpg', caption: 'a');
    await repo.setCover(actor, path: '/img/portada.jpg');

    final publicados = await repo.published();
    expect(publicados.first.isCover, isTrue);
    expect(publicados.length, 2);
  });

  test('un cajero no puede cambiar los anuncios', () async {
    final cashier = await user(UserRole.cashier);
    expect(
      () => repo.addBanner(cashier, path: '/img/x.jpg'),
      throwsA(isA<Exception>()),
    );
  });
}
