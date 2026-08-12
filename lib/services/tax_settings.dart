import 'package:flutter/foundation.dart';

import '../data/local/database.dart';

/// ¿Se desglosa IVA? **Apagado por defecto**: este negocio no factura, así que
/// el precio es el precio y no tiene por qué aparecer un impuesto en el ticket,
/// el carrito ni los reportes.
///
/// Se deja como interruptor y no como borrado porque el día que el cliente
/// facture, prenderlo devuelve el desglose sin tocar código.
///
/// Ojo con lo que NO hace: las ventas ya registradas guardaron su desglose y no
/// se reescriben (el historial no se falsea). Apagarlo afecta de aquí en
/// adelante, así que un reporte que cruce el antes y el después mezclará ambos
/// criterios.
class TaxSettings extends ChangeNotifier {
  TaxSettings(this._db);
  final AppDatabase _db;

  static const settingKey = 'tax_enabled';

  bool _enabled = false;
  bool get enabled => _enabled;

  /// Tasa a usar al cobrar: la del producto si el IVA está prendido, o cero.
  int rateFor(int productRateBps) => _enabled ? productRateBps : 0;

  /// Lee el ajuste guardado. Se llama una vez al arrancar.
  Future<void> load() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    _enabled = row?.value == 'true';
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: settingKey, value: '$value'));
    notifyListeners();
  }
}
