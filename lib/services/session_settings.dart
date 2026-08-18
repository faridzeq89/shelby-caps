import 'package:flutter/foundation.dart';

import '../data/local/database.dart';

/// ¿Se entra sin teclear el PIN?
///
/// **Apagado de fábrica.** Se prende cuando el mostrador lo atiende una sola
/// persona: ahí el PIN al arrancar no protege nada que el dueño no pueda hacer
/// de todos modos (entra como admin, y las autorizaciones de gerente ya se le
/// saltan por rol), y sí estorba — sobre todo en la versión web, donde cada
/// recarga de la pestaña lo vuelve a pedir.
///
/// Guarda el **id del perfil** y no un `true`: el día que haya un segundo
/// usuario, queda dicho cuál es el que entra solo en vez de adivinarlo.
///
/// Ojo con lo que NO hace: **no quita el login**. La pantalla de PIN sigue en
/// su lugar y se llega a ella con "Cerrar sesión" (para prestarle el aparato a
/// alguien más) y siempre que el perfil guardado ya no exista o esté
/// desactivado. Apagar el interruptor devuelve el arranque de siempre sin
/// tocar código.
class SessionSettings extends ChangeNotifier {
  SessionSettings(this._db);
  final AppDatabase _db;

  static const settingKey = 'auto_login_profile';

  int? _profileId;

  /// Perfil que entra sin PIN, o `null` si hay que teclearlo.
  int? get profileId => _profileId;
  bool get enabled => _profileId != null;

  /// Lee el ajuste guardado. Se llama una vez al arrancar.
  Future<void> load() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    _profileId = int.tryParse(row?.value ?? '');
    notifyListeners();
  }

  /// Prende el acceso directo para [profileId]. La pantalla de Acceso le pasa
  /// el usuario **que está en sesión**, para que nadie deje puesto a otro sin
  /// querer.
  Future<void> enableFor(int profileId) => _save('$profileId');

  Future<void> disable() => _save('');

  /// El perfil que debe entrar sin PIN, o `null` si hay que pedirlo.
  ///
  /// Resuelve contra los perfiles **activos**: si el usuario guardado se
  /// desactivó o se borró, devuelve `null` y la app cae a la pantalla de PIN.
  /// Esa es la salida segura — nadie se queda afuera y nadie entra de más.
  Future<Profile?> profileToAutoLogin() async {
    final id = _profileId;
    if (id == null) return null;
    for (final profile in await _db.activeProfiles()) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> _save(String value) async {
    _profileId = int.tryParse(value);
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: settingKey, value: value));
    notifyListeners();
  }
}
