import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/features/home/quick_destinations.dart';
import 'package:pos_boutique/services/quick_menu.dart';

/// La barra de abajo la decide el dueño. Lo que no puede pasar: que se quede
/// sin botones, que pierda la configuración al reabrir, o que un id viejo de
/// una versión anterior tumbe la pantalla.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('de fábrica salen las cuatro de siempre, con nombre', () async {
    final menu = QuickMenu(db);
    await menu.load();

    expect(menu.ids, ['inicio', 'vender', 'inventario', 'balance']);
    expect(menu.showLabels, isTrue);
  });

  test('los nombres se esconden a partir del sexto botón', () async {
    final menu = QuickMenu(db);
    await menu.save(['inicio', 'vender', 'inventario', 'balance']);
    expect(menu.showLabels, isTrue);
    expect(menu.labelSize, 11.5, reason: 'con 4 hay espacio de sobra');

    await menu
        .save(['inicio', 'vender', 'inventario', 'balance', 'cotizaciones']);
    expect(menu.showLabels, isTrue, reason: 'con 5 todavía caben');
    expect(menu.labelSize, 10.5, reason: 'pero un poco más chicos');

    await menu.save([
      'inicio', 'vender', 'inventario', 'balance', 'cotizaciones', 'apartados',
    ]);
    expect(menu.showLabels, isFalse, reason: 'con 6 ya no caben');
  });

  test('la configuración sobrevive a reabrir la app', () async {
    await QuickMenu(db).save(['vender', 'apartados', 'clientes']);

    final otra = QuickMenu(db); // como si la app arrancara de nuevo
    await otra.load();
    expect(otra.ids, ['vender', 'apartados', 'clientes']);
  });

  test('una barra vacía vuelve a lo de fábrica', () async {
    final menu = QuickMenu(db);
    await menu.save([]);

    expect(menu.ids, QuickMenu.defaults,
        reason: 'sin botones el dueño se quedaría sin forma de navegar');
  });

  test('todos los ids guardables existen de verdad', () {
    for (final d in quickDestinations) {
      expect(destinationById(d.id), isNotNull);
    }
    for (final id in QuickMenu.defaults) {
      expect(destinationById(id), isNotNull,
          reason: 'lo de fábrica tiene que existir');
    }
  });

  test('un id desconocido se ignora sin romper', () async {
    final menu = QuickMenu(db);
    await menu.save(['vender', 'esto-ya-no-existe', 'balance']);

    final resueltos =
        menu.ids.map(destinationById).whereType<QuickDestination>().toList();
    expect(resueltos.map((d) => d.id), ['vender', 'balance']);
  });

  test('las cuatro pestañas siguen siendo pestañas, no atajos', () {
    for (final id in QuickMenu.defaults) {
      expect(destinationById(id)!.isTab, isTrue,
          reason: 'deben conservar su estado, como el carrito de Vender');
    }
    expect(destinationById('cotizaciones')!.isTab, isFalse,
        reason: 'los atajos abren pantalla encima');
  });
}
