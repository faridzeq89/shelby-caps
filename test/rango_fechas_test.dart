import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/features/sales/sales_history_screen.dart';

/// El error de un día, en los dos sentidos. Ya lo cometí dos veces armando el
/// historial de ventas: una vez la lista terminaba un día antes (se comía las
/// ventas de hoy) y otra mostraba un día de más.
///
/// El calendario habla de **días inclusivos** ("del 1 al 15"); el repositorio y
/// los reportes hablan de un corte **`[desde, hasta)`**. Traducir entre los dos
/// es donde se pierde el día.
void main() {
  group('del calendario al corte', () {
    test('un solo día abarca ese día completo', () {
      final r = DateTimeRange(
          start: DateTime(2026, 8, 20), end: DateTime(2026, 8, 20));
      final c = cortePorDias(r);
      expect(c.desde, DateTime(2026, 8, 20));
      expect(c.hasta, DateTime(2026, 8, 21), reason: 'el corte va abierto');

      // Una venta a las 23:59 de ese día TIENE que entrar.
      final tarde = DateTime(2026, 8, 20, 23, 59, 59);
      expect(tarde.isBefore(c.hasta), isTrue);
      expect(tarde.isAfter(c.desde), isTrue);
    });

    test('la hora que traiga el calendario no recorta el rango', () {
      // El picker puede devolver las fechas con hora; el corte usa el DÍA.
      final r = DateTimeRange(
          start: DateTime(2026, 8, 1, 15, 30),
          end: DateTime(2026, 8, 15, 9, 5));
      final c = cortePorDias(r);
      expect(c.desde, DateTime(2026, 8, 1));
      expect(c.hasta, DateTime(2026, 8, 16));
      expect(DateTime(2026, 8, 1, 0, 1).isAfter(c.desde), isTrue,
          reason: 'una venta temprano del primer día entra');
      expect(DateTime(2026, 8, 15, 22).isBefore(c.hasta), isTrue,
          reason: 'una venta tarde del último día entra');
    });

    test('cruza fin de mes sin perder días', () {
      final c = cortePorDias(DateTimeRange(
          start: DateTime(2026, 7, 30), end: DateTime(2026, 8, 2)));
      expect(c.desde, DateTime(2026, 7, 30));
      expect(c.hasta, DateTime(2026, 8, 3));
    });
  });

  group('del corte al calendario', () {
    test('un periodo que termina a medianoche cae en el día anterior', () {
      // 'Mes pasado' en el Balance: [1 jul, 1 ago) -> del 1 al 31 de julio.
      final r = diasInclusivos(DateTime(2026, 7, 1), DateTime(2026, 8, 1));
      expect(r.start, DateTime(2026, 7, 1));
      expect(r.end.year, 2026);
      expect(r.end.month, 7);
      expect(r.end.day, 31);
    });

    test('un periodo que termina AHORA se queda en hoy', () {
      // Los presets del Balance ('7 días', 'Este mes') terminan en `now`, no a
      // medianoche. Restar un día aquí se comía las ventas de hoy.
      final ahora = DateTime(2026, 8, 20, 14, 31);
      final r = diasInclusivos(DateTime(2026, 8, 14), ahora);
      expect(r.end.day, 20, reason: 'hoy sigue incluido');

      // Y de regreso: el corte vuelve a abarcar todo el día de hoy.
      final c = cortePorDias(r);
      expect(c.hasta, DateTime(2026, 8, 21));
      expect(DateTime(2026, 8, 20, 23, 30).isBefore(c.hasta), isTrue);
    });

    test('ir y volver no mueve el rango', () {
      final original = DateTimeRange(
          start: DateTime(2026, 8, 5), end: DateTime(2026, 8, 9));
      final c = cortePorDias(original);
      final vuelta = diasInclusivos(c.desde, c.hasta);
      expect(vuelta.start, original.start);
      expect(vuelta.end.day, original.end.day);
      expect(vuelta.end.month, original.end.month);
    });
  });
}
