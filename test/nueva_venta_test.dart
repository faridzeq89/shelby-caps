import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/app.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/auth_controller.dart';

import 'widget_test.dart' show seedUser;

/// Al tocar "Vender" la app pregunta qué se va a hacer: cobrar o cotizar. Es
/// lo que el cliente ya conocía de otra app y por lo que no encontraba las
/// cotizaciones en el teléfono (ahí el botón vivía dentro de la hoja del
/// carrito).
///
/// Lo que no puede pasar: que elegir cotización no cambie nada, que cerrar la
/// hoja mueva de pantalla, o que la elección se quede pegada después de
/// guardar.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> abrirVender(WidgetTester tester) async {
    // Ventana alta y angosta: el caso del cliente (teléfono). La ventana de
    // 800x600 que trae el test por omisión deja la vitrina en 75 px y el
    // "carrito vacío" desborda, que es artefacto de la prueba y no del POS.
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final auth = AuthController(db);
    await auth.loginWithPin('5678');
    await tester.pumpWidget(BoutiquePosApp(auth: auth, db: db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vender').last, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  setUp(() async {
    await seedUser(db, name: 'Dueño', role: UserRole.admin, pin: '5678');
  });

  testWidgets('tocar Vender pregunta el tipo, sin "Venta libre"',
      (tester) async {
    await abrirVender(tester);

    expect(find.text('Nueva venta'), findsOneWidget);
    expect(find.text('Venta de productos'), findsOneWidget);
    expect(find.text('Cotización'), findsWidgets);
    expect(find.text('Venta libre'), findsNothing,
        reason: 'una venta sin líneas dejaría el ledger y la caja peleados');
  });

  testWidgets('elegir Cotización deja la pantalla en modo cotización',
      (tester) async {
    await abrirVender(tester);

    await tester.tap(find.text('Cotización').last);
    await tester.pumpAndSettle();

    expect(find.text('Nueva venta'), findsNothing, reason: 'la hoja se cierra');
    expect(find.text('COTIZACIÓN'), findsOneWidget,
        reason: 'el título dice en qué se va a convertir el carrito');
  });

  testWidgets('elegir Venta de productos deja el flujo de siempre',
      (tester) async {
    await abrirVender(tester);

    await tester.tap(find.text('Venta de productos'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva venta'), findsNothing);
    expect(find.text('COTIZACIÓN'), findsNothing);
    expect(find.text('VENTA'), findsOneWidget);
  });

  testWidgets('cerrar la hoja sin elegir no mueve de donde se está',
      (tester) async {
    await abrirVender(tester);
    expect(find.text('Nueva venta'), findsOneWidget);

    // Un toque fuera de la hoja es como se cierra en el teléfono.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Nueva venta'), findsNothing);
    expect(find.text('COTIZACIÓN'), findsNothing,
        reason: 'no se eligió nada, así que no hay modo que aplicar');
  });
}
