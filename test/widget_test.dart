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
    final key = find.text(digit);
    await tester.ensureVisible(key);
    await tester.pump();
    await tester.tap(key, warnIfMissed: false);
    await tester.pump();
  }
  final btn = find.widgetWithText(FilledButton, 'Entrar');
  await tester.ensureVisible(btn);
  await tester.pump();
  await tester.tap(btn, warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets(
    'Aceptación Fase 1: el cajero entra con PIN, cae en Inicio y el menú oculta lo de admin',
    (tester) async {
      await seedUser(db,
          name: 'Caja Ana', role: UserRole.cashier, pin: '5678');
      final auth = AuthController(db);

      await tester.pumpWidget(BoutiquePosApp(auth: auth, db: db));
      await tester.pumpAndSettle();

      await enterPin(tester, '5678');

      // Cae en la pantalla de Inicio (panel del día) con el bottom-nav de 4.
      expect(find.text('Ventas hoy'), findsOneWidget);
      expect(find.text('Inventario'), findsOneWidget);
      expect(find.text('Balance'), findsWidgets);

      // Abre el menú hamburguesa.
      await tester.tap(find.byIcon(Icons.menu).first);
      await tester.pumpAndSettle();

      // El cajero ve funciones básicas pero NO las de administración.
      expect(find.text('Punto de venta'), findsOneWidget);
      expect(find.text('Usuarios'), findsNothing);
      expect(find.text('Respaldo (nube)'), findsNothing);
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

      await tester.pumpWidget(BoutiquePosApp(auth: auth, db: db));
      await tester.pumpAndSettle();

      await enterPin(tester, '1234');

      // Tras entrar con el PIN inicial, se fuerza el cambio de PIN.
      expect(find.byType(ChangePinScreen), findsOneWidget);
    },
  );
}
