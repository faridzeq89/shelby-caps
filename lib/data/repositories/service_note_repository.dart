import 'package:drift/drift.dart';

import '../local/database.dart';

/// Notas de servicio (limpieza de tenis/gorra/bolsa): describen el trabajo
/// recibido, con el **precio cotizado** y las **notas adicionales** del
/// mostrador. No tocan inventario. El cobro es aparte, por una venta directa
/// (`SalesRepository.sellDirect`) que la liga con [markPaid].
class ServiceNoteRepository {
  ServiceNoteRepository(this._db);
  final AppDatabase _db;

  Future<List<ServiceNote>> all() => (_db.select(_db.serviceNotes)
        ..orderBy([
          (t) =>
              OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
        ]))
      .get();

  Future<ServiceNote?> byId(int id) =>
      (_db.select(_db.serviceNotes)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<ServiceNote> create({
    required String customerName,
    String? customerPhone,
    String? brand,
    String? size,
    String? color,
    required ServiceItemType itemType,
    int qty = 1,
    int? priceCents,
    String? notes,
  }) async {
    final folio = await _db.nextFolio('SV');
    final id = await _db.into(_db.serviceNotes).insert(
          ServiceNotesCompanion.insert(
            folio: folio,
            customerName: customerName.trim(),
            customerPhone: Value(_limpio(customerPhone)),
            brand: Value(_limpio(brand)),
            size: Value(_limpio(size)),
            color: Value(_limpio(color)),
            itemType: itemType,
            qty: Value(qty < 1 ? 1 : qty),
            priceCents: Value(priceCents),
            notes: Value(_limpio(notes)),
          ),
        );
    return (_db.select(_db.serviceNotes)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// Corrige una nota ya creada. El precio se acuerda a veces después de ver
  /// bien la pieza, el WhatsApp se teclea mal y el estado en que llegó se
  /// recuerda un minuto más tarde: sin esto, el único camino era volver a
  /// capturarla y perder su folio, que es el papel que se llevó el cliente.
  ///
  /// **Todos los campos se escriben con lo que se manda**, no solo los que
  /// cambiaron: nulo significa "déjalo vacío", no "no lo toques". La pantalla
  /// manda siempre el formulario completo tal como quedó.
  Future<void> updateDetails(
    int noteId, {
    required String customerName,
    String? customerPhone,
    String? brand,
    String? size,
    String? color,
    required ServiceItemType itemType,
    int qty = 1,
    int? priceCents,
    String? notes,
  }) async {
    await (_db.update(_db.serviceNotes)..where((t) => t.id.equals(noteId)))
        .write(ServiceNotesCompanion(
      customerName: Value(customerName.trim()),
      customerPhone: Value(_limpio(customerPhone)),
      brand: Value(_limpio(brand)),
      size: Value(_limpio(size)),
      color: Value(_limpio(color)),
      itemType: Value(itemType),
      qty: Value(qty < 1 ? 1 : qty),
      priceCents: Value(priceCents),
      notes: Value(_limpio(notes)),
    ));
  }

  /// Texto vacío se guarda como nulo, no como "": así la nota impresa y el
  /// detalle esconden el bloque en vez de dejar un renglón en blanco.
  static String? _limpio(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Liga la nota con la venta que la cobró. Sin columna de estado aparte:
  /// pendiente es `saleId == null`, cobrada es `saleId != null`.
  Future<void> markPaid(int noteId, String saleId) =>
      (_db.update(_db.serviceNotes)..where((t) => t.id.equals(noteId)))
          .write(ServiceNotesCompanion(saleId: Value(saleId)));
}
