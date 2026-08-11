import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/supplier_repository.dart';

void main() {
  late AppDatabase db;
  late SupplierRepository repo;
  late CatalogRepository catalog;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SupplierRepository(db);
    catalog = CatalogRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> profile(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('crea, edita y archiva un proveedor', () async {
    final actor = await profile(UserRole.admin);
    final id = await repo.create(
        actor: actor, name: 'Gorras MX', phone: '555', contact: 'Luis');
    var s = await repo.byId(id);
    expect(s!.name, 'Gorras MX');
    expect(s.phone, '555');

    await repo.update(actor: actor, id: id, name: 'Gorras MX SA', phone: '556');
    s = await repo.byId(id);
    expect(s!.name, 'Gorras MX SA');
    expect(s.phone, '556');

    await repo.setActive(actor, id, false);
    expect(await repo.all(), isEmpty); // activeOnly por defecto
    expect(await repo.all(activeOnly: false), hasLength(1));
  });

  test('el cajero no puede crear proveedores', () async {
    final caja = await profile(UserRole.cashier);
    expect(
      () => repo.create(actor: caja, name: 'X'),
      throwsA(isA<PermissionException>()),
    );
  });

  test('liga y deshace el proveedor de un producto', () async {
    final actor = await profile(UserRole.admin);
    final sid = await repo.create(actor: actor, name: 'Prov');
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'C'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: 'Gorra', categoryId: catId, basePriceCents: 10000));

    await catalog.updateProductSupplier(
        actor: actor, productId: pid, supplierId: sid);
    var p = await catalog.productById(pid);
    expect(p!.supplierId, sid);

    await catalog.updateProductSupplier(
        actor: actor, productId: pid, supplierId: null);
    p = await catalog.productById(pid);
    expect(p!.supplierId, isNull);
  });
}
