import '../data/local/database.dart';

/// "Mensaje del día": la primera vez que se entra cada día, la app saluda al
/// dueño con una frase motivadora. Guarda **solo** la fecha del último aviso en
/// `app_settings` (mismo patrón que `TaxSettings`/`SessionSettings`, sin
/// migración de esquema). Es por dispositivo, que es justo lo que se quiere:
/// "la primera vez del día en ESTE aparato".
class MotdSettings {
  MotdSettings(this._db);
  final AppDatabase _db;

  static const settingKey = 'motd_last_shown'; // guarda 'yyyy-mm-dd'

  static String _todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  /// ¿Ya toca mostrarlo? (No se ha mostrado hoy en este dispositivo.)
  Future<bool> shouldShowToday() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    return (row?.value.trim() ?? '') != _todayKey();
  }

  Future<void> markShownToday() async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: settingKey, value: _todayKey()));
  }

  /// La frase de hoy: determinista por fecha (la misma todo el día, cambia al
  /// día siguiente), así no se repite dos veces el mismo día ni depende de
  /// azar. Índice a partir del día para que rote por toda la lista.
  static String phraseForToday([DateTime? now]) {
    final n = now ?? DateTime.now();
    final serial = n.year * 372 + n.month * 31 + n.day;
    return phrases[serial % phrases.length];
  }

  /// Frases motivadoras, bien mexicanas. Suben el ánimo para el mostrador sin
  /// pasarse de lanza; usan el habla popular que pidió el dueño.
  static const phrases = <String>[
    'Hoy le vas a vender chingón. ¡Órale, arránquese esa venta!',
    'Eres el más mamalón del mostrador. A darle con todo, mi rey.',
    'Ni de chiste te rajas hoy. ¡Con esa actitud se vende más!',
    'Échale ganas, compa: hoy caen ventas de las buenas.',
    'Hoy se factura chingón. ¡Vámonos recio, campeón!',
    'Con esa garra vendes hasta el aire. ¡A chingarle bonito!',
    'Arriba ese ánimo, que hoy vienes en modo chingón.',
    'Cada cliente que entra es una oportunidad. ¡No te achiques, dale!',
    'Hoy toca vender como los meros meros. ¡Con todo, mi buen!',
    'El que es chingón, es chingón. Y hoy ese eres tú.',
    'Ponte trucha y véndete estas gorras solitas. ¡Órale pues!',
    'Hoy vas a andar bien mamalón cerrando ventas. ¡A darle!',
    'Nada te para hoy, compa. ¡A romperla en el mostrador!',
    'Sonríele al cliente y véndele chingón. ¡Así se hace, crack!',
  ];
}
