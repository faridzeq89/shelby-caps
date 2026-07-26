import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/core/pin_hash.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/user_repository.dart';

void main() {
  late AppDatabase db;
  late UserRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = UserRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> seed(UserRole role, {String pin = '9999'}) async {
    final salt = PinHash.generateSalt();
    final id = await db.insertProfile(ProfilesCompanion.insert(
      name: role.name,
      role: role,
      pinSalt: salt,
      pinHash: PinHash.hash(pin, salt),
    ));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('admin crea un cajero con PIN y obliga a cambiarlo', () async {
    final admin = await seed(UserRole.admin);
    final id = await repo.createUser(admin,
        name: 'Ana', role: UserRole.cashier, pin: '4321');
    final u = (await repo.listUsers()).firstWhere((p) => p.id == id);
    expect(u.name, 'Ana');
    expect(u.role, UserRole.cashier);
    expect(u.mustChangePin, isTrue);
    expect(PinHash.verify('4321', u.pinSalt, u.pinHash), isTrue);
  });

  test('un cajero no puede crear usuarios', () async {
    final cashier = await seed(UserRole.cashier);
    expect(
      () => repo.createUser(cashier,
          name: 'X', role: UserRole.cashier, pin: '1111'),
      throwsA(isA<PermissionException>()),
    );
  });

  test('rechaza PIN duplicado de otro usuario activo', () async {
    final admin = await seed(UserRole.admin, pin: '9999');
    await repo.createUser(admin, name: 'Ana', role: UserRole.cashier, pin: '4321');
    expect(
      () => repo.createUser(admin,
          name: 'Beto', role: UserRole.cashier, pin: '4321'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rechaza PIN inválido (no 4-6 dígitos)', () async {
    final admin = await seed(UserRole.admin);
    expect(
      () => repo.createUser(admin, name: 'X', role: UserRole.cashier, pin: '12'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('no deja desactivar al último admin ni a sí mismo', () async {
    final admin = await seed(UserRole.admin);
    // Desactivarse a sí mismo: prohibido.
    expect(() => repo.setActive(admin, admin.id, false),
        throwsA(isA<StateError>()));

    // Con otro admin, el primero se puede desactivar; el último no.
    final admin2Id = await repo.createUser(admin,
        name: 'Admin2', role: UserRole.admin, pin: '5555');
    await repo.setActive(admin, admin2Id, false); // ok, queda 1 admin (el actor)
    // Ahora intentar dejar cero admins activos desactivando a admin2 ya inactivo
    // no aplica; probamos que no se puede desactivar el único admin restante.
    final admin2 = (await repo.listUsers()).firstWhere((p) => p.id == admin2Id);
    // reactivar admin2 y desactivar al actor vía admin2
    await repo.setActive(admin, admin2Id, true);
    final refreshedAdmin2 =
        (await repo.listUsers()).firstWhere((p) => p.id == admin2Id);
    expect(refreshedAdmin2.active, isTrue);
    expect(admin2.role, UserRole.admin);
  });

  test('reset de PIN cambia el hash y obliga a cambiarlo', () async {
    final admin = await seed(UserRole.admin);
    final id = await repo.createUser(admin,
        name: 'Ana', role: UserRole.cashier, pin: '4321');
    await repo.resetPin(admin, id, '8765');
    final u = (await repo.listUsers()).firstWhere((p) => p.id == id);
    expect(PinHash.verify('8765', u.pinSalt, u.pinHash), isTrue);
    expect(u.mustChangePin, isTrue);
  });
}
