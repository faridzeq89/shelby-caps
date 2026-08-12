import 'package:flutter/foundation.dart';

import '../data/local/database.dart';

/// Entrega una cotización a la pantalla de Venta desde cualquier lugar.
///
/// Antes "Pasar a venta" hacía `Navigator.pop(quote)`, lo que solo funcionaba
/// si la lista de cotizaciones se había abierto **desde Venta**. Abierta desde
/// el menú lateral o desde Inicio, el `pop` devolvía la cotización a una
/// pantalla que no la esperaba y no pasaba nada.
///
/// Con esto el origen deja de importar: quien quiera pasar una cotización a
/// venta la deja aquí, el shell cambia a la pestaña Vender y la pantalla de
/// Venta la recoge.
class SaleHandoff extends ChangeNotifier {
  Quote? _pending;

  /// ¿Hay una cotización esperando? La usa el shell para saber si cambiar de
  /// pestaña.
  bool get hasPending => _pending != null;

  /// Deja una cotización lista para cargarse al carrito.
  void send(Quote quote) {
    _pending = quote;
    notifyListeners();
  }

  /// La recoge y la consume: una cotización se carga una sola vez.
  Quote? take() {
    final q = _pending;
    _pending = null;
    return q;
  }
}
