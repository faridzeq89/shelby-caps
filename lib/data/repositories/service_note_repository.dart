import 'package:drift/drift.dart';

import '../local/database.dart';

/// Notas de servicio (limpieza de tenis/gorra/bolsa): solo describen el
/// trabajo recibido, sin precio ni inventario. El cobro es aparte, por una
/// venta directa (`SalesRepository.sellDirect`) que la liga con [markPaid].
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
    String? brand,
    String? color,
    required ServiceItemType itemType,
  }) async {
    final folio = await _db.nextFolio('SV');
    final id = await _db.into(_db.serviceNotes).insert(
          ServiceNotesCompanion.insert(
            folio: folio,
            customerName: customerName,
            brand: Value(brand),
            color: Value(color),
            itemType: itemType,
          ),
        );
    return (_db.select(_db.serviceNotes)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// Liga la nota con la venta que la cobró. Sin columna de estado aparte:
  /// pendiente es `saleId == null`, cobrada es `saleId != null`.
  Future<void> markPaid(int noteId, String saleId) =>
      (_db.update(_db.serviceNotes)..where((t) => t.id.equals(noteId)))
          .write(ServiceNotesCompanion(saleId: Value(saleId)));
}
