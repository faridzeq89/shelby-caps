import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/auth_controller.dart';
import 'package:pos_boutique/services/session_settings.dart';

import 'package:pos_boutique/core/pin_hash.dart';

/// El acceso directo (Ajustes → Acceso) salta el PIN al arrancar. Lo que no
/// puede pasar: que deje entrar a un usuario que ya se desactivó, que se
/// pierda al reabrir la app, o que después de "Cerrar sesión" vuelva a meter
/// al dueño solo (el escape para prestar el aparato dejaría de existir).
Future<void> seedUser(AppDatabase db, String name) async {
  final salt = PinHash.generateSalt();
  await db.insertProfile(ProfilesCompanion.insert(
    name: name,
    role: UserRole.admin,
    pinSalt: salt,
    pinHash: PinHash.hash('4321', salt),
  ));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('de fábrica está apagado: siempre se pide el PIN', () async {
    final session = SessionSettings(db);
    await session.load();

    expect(session.enabled, isFalse);
    expect(await session.profileToAutoLogin(), isNull);
  });

  test('prendido devuelve al dueño, y sobrevive a reabrir la app', () async {
    await seedUser(db, 'Dueño');
    final duenio = (await db.activeProfiles()).single;

    await SessionSettings(db).enableFor(duenio.id);

    // Una instancia nueva es lo que pasa al reabrir la app.
    final alReabrir = SessionSettings(db);
    await alReabrir.load();

    expect(alReabrir.enabled, isTrue);
    expect((await alReabrir.profileToAutoLogin())?.id, duenio.id);
  });

  test('si el usuario guardado se desactiva, se vuelve a pedir el PIN',
      () async {
    await seedUser(db, 'Dueño');
    final duenio = (await db.activeProfiles()).single;
    final session = SessionSettings(db);
    await session.enableFor(duenio.id);

    await db.updateProfile(duenio.copyWith(active: false));

    expect(session.enabled, isTrue, reason: 'el ajuste sigue guardado');
    expect(await session.profileToAutoLogin(), isNull,
        reason: 'pero no puede entrar: cae a la pantalla de PIN');
  });

  test('apagarlo devuelve el arranque de siempre', () async {
    await seedUser(db, 'Dueño');
    final duenio = (await db.activeProfiles()).single;
    final session = SessionSettings(db);
    await session.enableFor(duenio.id);

    await session.disable();

    expect(session.enabled, isFalse);
    expect(await session.profileToAutoLogin(), isNull);
  });

  test('cerrar sesión saca al dueño aunque el acceso directo esté prendido',
      () async {
    await seedUser(db, 'Dueño');
    final duenio = (await db.activeProfiles()).single;
    final auth = AuthController(db);
    auth.loginAs(duenio);
    expect(auth.isLoggedIn, isTrue);

    auth.logout();

    expect(auth.isLoggedIn, isFalse,
        reason: 'es el escape para prestarle el aparato a alguien más');
  });
}
