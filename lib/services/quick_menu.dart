import 'package:flutter/foundation.dart';

import '../data/local/database.dart';

/// Qué botones aparecen en la barra de abajo y en qué orden.
///
/// Cada tienda usa la app distinto: una vive en Vender y Balance, otra necesita
/// Apartados a la mano. Por eso lo decide el dueño y no nosotros.
///
/// Se guarda como una lista de ids separados por coma en `app_settings`.
class QuickMenu extends ChangeNotifier {
  QuickMenu(this._db);
  final AppDatabase _db;

  static const settingKey = 'quick_menu';

  /// Con lo que sale de fábrica: las cuatro de siempre.
  static const defaults = ['inicio', 'vender', 'inventario', 'balance'];

  /// Hasta aquí los botones llevan nombre. Con seis, la etiqueta más larga
  /// ("Devoluciones") queda tan apretada que se corta y deja de servir.
  static const labelLimit = 5;

  /// Con cinco botones el nombre se dibuja un poco más chico para que quepa.
  static const tightFrom = 5;

  List<String> _ids = List.of(defaults);
  List<String> get ids => List.unmodifiable(_ids);

  /// ¿Se dibujan las etiquetas? Con 5 o menos sí; de 6 en adelante no.
  bool get showLabels => _ids.length <= labelLimit;

  /// Tamaño del nombre según cuántos botones haya.
  double get labelSize => _ids.length >= tightFrom ? 10.5 : 11.5;

  Future<void> load() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    final raw = row?.value.trim();
    if (raw == null || raw.isEmpty) {
      _ids = List.of(defaults);
    } else {
      _ids = raw.split(',').where((s) => s.trim().isNotEmpty).toList();
    }
    notifyListeners();
  }

  Future<void> save(List<String> ids) async {
    // Una barra vacía dejaría al dueño sin forma de navegar salvo el menú
    // lateral; se vuelve a lo de fábrica en vez de permitirlo.
    _ids = ids.isEmpty ? List.of(defaults) : List.of(ids);
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
            key: settingKey, value: _ids.join(',')));
    notifyListeners();
  }

  Future<void> reset() => save(List.of(defaults));
}
