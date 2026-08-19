import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/motd_settings.dart';

/// El mensaje del día se muestra UNA vez por día por dispositivo. Guarda solo
/// la fecha en `app_settings` (sin migración). Lo que no puede pasar: mostrarse
/// dos veces el mismo día, o quedar sin frase.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('de fábrica toca mostrarlo; tras marcarlo, ya no', () async {
    final motd = MotdSettings(db);
    expect(await motd.shouldShowToday(), isTrue,
        reason: 'nunca se ha mostrado en este aparato');

    await motd.markShownToday();
    expect(await motd.shouldShowToday(), isFalse,
        reason: 'ya se mostró hoy, no se repite');
  });

  test('phraseForToday: siempre en la lista y estable el mismo día', () {
    final d = DateTime(2026, 8, 19, 8, 0);
    final again = DateTime(2026, 8, 19, 23, 59);
    expect(MotdSettings.phrases, contains(MotdSettings.phraseForToday(d)));
    expect(MotdSettings.phraseForToday(d), MotdSettings.phraseForToday(again),
        reason: 'la misma frase todo el día');
  });

  test('la frase rota entre días', () {
    // En 14 días consecutivos deben salir varias frases distintas (no una fija).
    final vistas = <String>{};
    for (var i = 0; i < 14; i++) {
      vistas.add(MotdSettings.phraseForToday(DateTime(2026, 8, 1 + i)));
    }
    expect(vistas.length, greaterThan(1));
  });
}
