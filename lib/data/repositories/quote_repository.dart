import 'package:drift/drift.dart';

import '../local/database.dart';

/// Un renglón de cotización al momento de guardarla (desde el carrito).
class QuoteDraftLine {
  const QuoteDraftLine({
    required this.variantId,
    required this.qty,
    required this.unitPriceCents,
    this.lineDiscountCents = 0,
  });
  final int variantId;
  final int qty;
  final int unitPriceCents;
  final int lineDiscountCents;

  int get grossCents => unitPriceCents * qty;
  int get netCents => (grossCents - lineDiscountCents).clamp(0, grossCents);
}

/// Cotizaciones: guardar un carrito sin cobrar, listarlas, cancelarlas y
/// marcarlas convertidas cuando se pasan a venta. No tocan inventario ni caja.
class QuoteRepository {
  QuoteRepository(this._db);
  final AppDatabase _db;

  /// Guarda una cotización con sus renglones. [validDays] nulo = sin caducidad.
  Future<Quote> create({
    required Profile actor,
    required List<QuoteDraftLine> lines,
    int? customerId,
    String? notes,
    int? validDays,
  }) async {
    if (lines.isEmpty) throw ArgumentError('La cotización no tiene renglones');
    final subtotal = lines.fold<int>(0, (s, l) => s + l.grossCents);
    final total = lines.fold<int>(0, (s, l) => s + l.netCents);
    final folio = await _db.nextFolio('COT');
    final now = DateTime.now();

    return _db.transaction(() async {
      final id = await _db.into(_db.quotes).insert(
            QuotesCompanion.insert(
              folio: folio,
              status: QuoteStatus.open,
              subtotalCents: subtotal,
              totalCents: total,
              customerId: Value(customerId),
              notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
              expiresAt: Value(
                  validDays == null ? null : now.add(Duration(days: validDays))),
            ),
          );
      for (final l in lines) {
        await _db.into(_db.quoteLines).insert(
              QuoteLinesCompanion.insert(
                quoteId: id,
                variantId: l.variantId,
                qty: l.qty,
                unitPriceCents: l.unitPriceCents,
                lineDiscountCents: Value(l.lineDiscountCents),
                lineTotalCents: l.netCents,
              ),
            );
      }
      await _audit(actor, 'create_quote', id.toString(), folio);
      return (_db.select(_db.quotes)..where((t) => t.id.equals(id))).getSingle();
    });
  }

  /// Cotizaciones vigentes (no convertidas ni canceladas), recientes primero.
  Future<List<Quote>> open() => (_db.select(_db.quotes)
        ..where((t) => t.status.equalsValue(QuoteStatus.open))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
        ]))
      .get();

  Future<List<Quote>> all() => (_db.select(_db.quotes)
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
        ]))
      .get();

  Future<List<QuoteLine>> linesOf(int quoteId) =>
      (_db.select(_db.quoteLines)..where((t) => t.quoteId.equals(quoteId))).get();

  /// Cambia el precio unitario de un renglón (p. ej. un servicio cuyo precio se
  /// define hasta ver la prenda) y recalcula los totales de la cotización.
  Future<void> updateLinePrice(
      Profile actor, int quoteLineId, int unitPriceCents) async {
    await _db.transaction(() async {
      final line = await (_db.select(_db.quoteLines)
            ..where((t) => t.id.equals(quoteLineId)))
          .getSingleOrNull();
      if (line == null) return;
      final gross = unitPriceCents * line.qty;
      final net = (gross - line.lineDiscountCents).clamp(0, gross);
      await (_db.update(_db.quoteLines)..where((t) => t.id.equals(quoteLineId)))
          .write(QuoteLinesCompanion(
              unitPriceCents: Value(unitPriceCents),
              lineTotalCents: Value(net)));
      await _recomputeTotals(line.quoteId);
      await _audit(actor, 'edit_quote_line', line.quoteId.toString(),
          'linea=$quoteLineId precio=$unitPriceCents');
    });
  }

  Future<void> _recomputeTotals(int quoteId) async {
    final lines = await linesOf(quoteId);
    final subtotal = lines.fold<int>(0, (s, l) => s + l.unitPriceCents * l.qty);
    final total = lines.fold<int>(0, (s, l) => s + l.lineTotalCents);
    await (_db.update(_db.quotes)..where((t) => t.id.equals(quoteId))).write(
        QuotesCompanion(
            subtotalCents: Value(subtotal), totalCents: Value(total)));
  }

  Future<void> cancel(Profile actor, int quoteId) async {
    await _db.transaction(() async {
      await (_db.update(_db.quotes)..where((t) => t.id.equals(quoteId)))
          .write(const QuotesCompanion(status: Value(QuoteStatus.cancelled)));
      await _audit(actor, 'cancel_quote', quoteId.toString(), 'cancelada');
    });
  }

  /// Marca una cotización como convertida y la liga a la venta [saleId].
  Future<void> markConverted(int quoteId, String saleId) async {
    await (_db.update(_db.quotes)..where((t) => t.id.equals(quoteId))).write(
        QuotesCompanion(
            status: const Value(QuoteStatus.converted),
            convertedSaleId: Value(saleId)));
  }

  Future<void> _audit(
      Profile actor, String action, String entityId, String detail) {
    return _db.into(_db.auditLog).insert(
          AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: 'quote',
            entityId: Value(entityId),
            detail: Value(detail),
          ),
        );
  }
}
