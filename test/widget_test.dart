import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pos_boutique/app.dart';
import 'package:pos_boutique/core/pin_hash.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/features/admin/admin_screen.dart';
import 'package:pos_boutique/features/auth/change_pin_screen.dart';
import 'package:pos_boutique/services/auth_controller.dart';

/// Inserta un usuario con un PIN conocido para las pruebas.
Future<void> seedUser(
  AppDatabase db, {
  required String name,
  required UserRole role,
  required String pin,
}) async {
  final salt = PinHash.generateSalt();
  await db.insertProfile(
    ProfilesCompanion.insert(
      name: name,
      role: role,
      pinSalt: salt,
      pinHash: PinHash.hash(pin, salt),
    ),
  );
}

Future<void> enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets(
    'Aceptación Fase 1: el cajero entra con PIN, ve su rol y no accede a admin',
    (tester) async {
      await seedUser(db,
          name: 'Caja Ana', role: UserRole.cashier, pin: '5678');
      final auth = AuthController(db);

      await tester.pumpWidget(BoutiquePosApp(auth: auth));
      await tester.pumpAndSettle();

      await enterPin(tester, '5678');

      // Ve su nombre y su rol.
      expect(find.text('Hola, Caja Ana'), findsOneWidget);
      expect(find.text('Cajero'), findsOneWidget);

      // No hay entrada a administración para el cajero.
      expect(find.text('Administración'), findsNothing);
    },
  );

  testWidgets(
    'La pantalla de administración niega el acceso a un no-admin',
    (tester) async {
      await seedUser(db,
          name: 'Caja Ana', role: UserRole.cashier, pin: '5678');
      final auth = AuthController(db);
      await auth.loginWithPin('5678');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: auth,
          child: const MaterialApp(home: AdminScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Acceso denegado'), findsOneWidget);
    },
  );

  testWidgets(
    'Primer arranque: crea admin con PIN 1234 y obliga a cambiarlo',
    (tester) async {
      final auth = AuthController(db);
      await auth.ensureSeedAdmin();

      await tester.pumpWidget(BoutiquePosApp(auth: auth));
      await tester.pumpAndSettle();

      await enterPin(tester, '1234');

      // Tras entrar con el PIN inicial, se fuerza el cambio de PIN.
      expect(find.byType(ChangePinScreen), findsOneWidget);
    },
  );
}
