import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/database.dart';

/// Una pieza recibida en una nota de servicio (tipo + marca/talla/color +
/// cantidad). Una nota puede tener varias (2 tenis Nike + 1 gorra roja). Se
/// guardan como JSON en `service_notes.items_json`.
class ServiceItem {
  const ServiceItem({
    required this.itemType,
    this.brand,
    this.size,
    this.color,
    this.qty = 1,
  });

  final ServiceItemType itemType;
  final String? brand;
  final String? size;
  final String? color;
  final int qty;

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Map<String, dynamic> toJson() => {
        'type': itemType.name,
        if (_clean(brand) != null) 'brand': _clean(brand),
        if (_clean(size) != null) 'size': _clean(size),
        if (_clean(color) != null) 'color': _clean(color),
        'qty': qty < 1 ? 1 : qty,
      };

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        itemType: ServiceItemType.values.firstWhere(
            (t) => t.name == j['type'],
            orElse: () => ServiceItemType.tenis),
        brand: _clean(j['brand'] as String?),
        size: _clean(j['size'] as String?),
        color: _clean(j['color'] as String?),
        qty: (j['qty'] as num?)?.toInt() ?? 1,
      );
}

/// Las piezas de una nota. Si trae `items_json` lo usa; si no (nota vieja de una
/// sola pieza), reconstruye una pieza desde las columnas del encabezado. Así el
/// resto del código siempre trabaja con una lista, sin ramas por versión.
List<ServiceItem> serviceNoteItems(ServiceNote note) {
  final raw = note.itemsJson;
  if (raw != null && raw.trim().isNotEmpty) {
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(ServiceItem.fromJson)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (_) {
      // JSON corrupto: cae al artículo del encabezado en vez de romper.
    }
  }
  return [
    ServiceItem(
      itemType: note.itemType,
      brand: note.brand,
      size: note.size,
      color: note.color,
      qty: note.qty,
    ),
  ];
}

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

  /// La 1ª pieza y el total de piezas se denormalizan en el encabezado para el
  /// resumen de la lista; la lista completa vive en `items_json`.
  ServiceNotesCompanion _header(
    List<ServiceItem> items, {
    required String customerName,
    String? customerPhone,
    int? priceCents,
    String? notes,
  }) {
    final first = items.first;
    final totalQty =
        items.fold<int>(0, (s, i) => s + (i.qty < 1 ? 1 : i.qty));
    return ServiceNotesCompanion(
      customerName: Value(customerName.trim()),
      customerPhone: Value(_limpio(customerPhone)),
      brand: Value(_limpio(first.brand)),
      size: Value(_limpio(first.size)),
      color: Value(_limpio(first.color)),
      itemType: Value(first.itemType),
      qty: Value(totalQty),
      priceCents: Value(priceCents),
      notes: Value(_limpio(notes)),
      itemsJson: Value(jsonEncode(items.map((e) => e.toJson()).toList())),
    );
  }

  Future<ServiceNote> create({
    required String customerName,
    String? customerPhone,
    int? priceCents,
    String? notes,
    required List<ServiceItem> items,
  }) async {
    assert(items.isNotEmpty, 'Una nota necesita al menos una pieza');
    final folio = await _db.nextFolio('SV');
    final id = await _db.into(_db.serviceNotes).insert(
          _header(items,
                  customerName: customerName,
                  customerPhone: customerPhone,
                  priceCents: priceCents,
                  notes: notes)
              .copyWith(folio: Value(folio)),
        );
    return (_db.select(_db.serviceNotes)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// Corrige una nota ya creada. Escribe **todo** el formulario tal como quedó
  /// (nulo = "déjalo vacío", no "no lo toques"): sin esto, el único camino era
  /// recapturar la nota y perder su folio, que es el papel que se llevó el
  /// cliente.
  Future<void> updateDetails(
    int noteId, {
    required String customerName,
    String? customerPhone,
    int? priceCents,
    String? notes,
    required List<ServiceItem> items,
  }) async {
    await (_db.update(_db.serviceNotes)..where((t) => t.id.equals(noteId)))
        .write(_header(items,
            customerName: customerName,
            customerPhone: customerPhone,
            priceCents: priceCents,
            notes: notes));
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
