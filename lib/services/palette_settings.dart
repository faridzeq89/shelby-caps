import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/ui_kit.dart';
import '../data/local/database.dart';

/// Guarda el color y el fondo que eligió el dueño, y repinta la app con ellos.
///
/// Solo se guardan **dos** datos —el color y si el fondo es oscuro—; el resto
/// de la paleta se recalcula, así nunca queda una combinación ilegible guardada.
class PaletteSettings extends ChangeNotifier {
  PaletteSettings(this._db);
  final AppDatabase _db;

  static const seedKey = 'theme_seed';
  static const darkKey = 'theme_dark';

  /// De fábrica: vino tirando a rojo sobre gris casi negro.
  static const defaultSeed = Color(0xFFA81C22);
  static const defaultDark = true;

  Palette _palette = Palette.fromSeed(defaultSeed, dark: defaultDark);
  Palette get palette => _palette;

  Color get seed => _palette.seed;
  bool get dark => _palette.dark;

  Future<String?> _get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value.trim();
  }

  /// Lee lo guardado y repinta. Se llama una vez al arrancar.
  Future<void> load() async {
    final rawSeed = await _get(seedKey);
    final rawDark = await _get(darkKey);
    final seed = _parse(rawSeed) ?? defaultSeed;
    final dark = rawDark == null ? defaultDark : rawDark == 'true';
    _apply(Palette.fromSeed(seed, dark: dark));
  }

  Future<void> setSeed(Color seed) => _save(seed, dark);
  Future<void> setDark(bool dark) => _save(seed, dark);
  Future<void> reset() => _save(defaultSeed, defaultDark);

  Future<void> _save(Color seed, bool dark) async {
    _apply(Palette.fromSeed(seed, dark: dark));
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: seedKey, value: _hex(seed)));
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: darkKey, value: '$dark'));
  }

  void _apply(Palette p) {
    _palette = p;
    AppColors.apply(p);
    notifyListeners();
  }

  static String _hex(Color c) {
    int b(double v) => (v * 255).round().clamp(0, 255);
    return '#${b(c.r).toRadixString(16).padLeft(2, '0')}'
            '${b(c.g).toRadixString(16).padLeft(2, '0')}'
            '${b(c.b).toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  /// Acepta `#RRGGBB` o `RRGGBB`. Devuelve `null` si no es un color válido, y
  /// entonces se usa el de fábrica en vez de dejar la app sin colores.
  static Color? _parse(String? raw) {
    if (raw == null) return null;
    final s = raw.replaceAll('#', '').trim();
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// Público para que la pantalla valide lo que escribe el dueño.
  static Color? parseHex(String raw) => _parse(raw);
  static String toHex(Color c) => _hex(c);
}
