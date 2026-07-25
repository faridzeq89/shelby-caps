import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../local/database.dart';
import 'sales_repository.dart' show CheckoutLine;

class LayawayCreateResult {
  const LayawayCreateResult({
    required this.saleId,
    required this.folio,
    required this.totalCents,
    required this.depositRequiredCents,
    required this.balanceCents,
  });
  final String saleId;
  final String folio;
  final int totalCents;
  final int depositRequiredCents;
  final int balanceCents;
}

/// Apartado con su saldo y datos de vencimiento (para la lista).
class LayawaySummary {
  const LayawaySummary(this.sale, this.terms, this.customerName, this.balanceCents);
  final Sale sale;
  final LayawayTerm terms;
  final String? customerName;
  final int balanceCents;
}

/// Apartados (layaway). Un apartado es una venta con `status='layaway'`: las
/// piezas se **reservan** (movimientos `reserve`, siguen en on_hand pero no
/// disponibles). Al liquidar se hace `release` + `sale`.
class LayawayRepository {
  LayawayRepository(this._db);
  final AppDatabase _db;

  static const depositPercent = 30; // política Fase 0
  static const termDays = 30;
  static const _uuid = Uuid();

  Future<int> createCustomer(String name, String? phone) => _db
      .into(_db.customers)
      .insert(CustomersCompanion.insert(name: name, phone: Value(phone)));

  Future<int> balance(String saleId) async {
    final sale =
        await (_db.select(_db.sales)..where((t) => t.id.equals(saleId))).getSingle();
    final pays = await (_db.select(_db.payments)
          ..where((t) => t.saleId.equals(saleId)))
        .get();
    final paid = pays.fold<int>(0, (s, p) => s + p.amountCents);
    return sale.totalCents - paid;
  }

  Future<LayawayCreateResult> createLayaway({
    required Profile actor,
    required int locationId,
    required int customerId,
    required List<CheckoutLine> lines,
    required int depositCents,
    DateTime? dueDate,
    PaymentMethod depositMethod = PaymentMethod.cash,
  }) async {
    if (lines.isEmpty) throw ArgumentError('El apartado necesita piezas');
    final total = lines.fold<int>(0, (s, l) => s + l.unitPriceCents * l.qty);
    final depositRequired = (total * depositPercent / 100).round();
    if (depositCents < depositRequired) {
      throw ArgumentError('El anticipo mínimo es $depositRequired ($depositPercent%)');
    }

    var subtotal = 0, tax = 0;
    for (final l in lines) {
      final bd = taxIncludedBreakdown(
          l.unitPriceCents * l.qty, l.product.taxRateBps);
      subtotal += bd.baseCents;
      tax += bd.taxCents;
    }

    final saleId = _uuid.v4();
    final due = dueDate ?? DateTime.now().add(const Duration(days: termDays));

    return _db.transaction(() async {
      final folio = await _takeFolio();
      await _db.into(_db.sales).insert(SalesCompanion.insert(
            id: saleId,
            folio: folio,
            locationId: locationId,
            cashierId: actor.id,
            customerId: Value(customerId),
            status: SaleStatus.layaway,
            subtotalCents: subtotal,
            taxCents: tax,
            totalCents: total,
          ));
      for (final l in lines) {
        final bd = taxIncludedBreakdown(
            l.unitPriceCents * l.qty, l.product.taxRateBps);
        await _db.into(_db.saleLines).insert(SaleLinesCompanion.insert(
              saleId: saleId,
              variantId: l.variant.id,
              qty: l.qty,
              unitPriceCents: l.unitPriceCents,
              taxCents: bd.taxCents,
              lineTotalCents: l.unitPriceCents * l.qty,
            ));
        // Reserva: la pieza sigue en on_hand pero deja de estar disponible.
        await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: l.variant.id,
                locationId: locationId,
                qty: l.qty,
                type: MovementType.reserve,
                userId: Value(actor.id),
                referenceType: const Value('layaway'),
                referenceId: Value(saleId)));
      }
      await _db.into(_db.layawayTerms).insert(LayawayTermsCompanion.insert(
            saleId: saleId,
            depositRequiredCents: depositRequired,
            dueDate: due,
            expiresAt: due,
            status: LayawayStatus.active,
          ));
      await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: saleId,
            method: depositMethod,
            amountCents: depositCents,
            reference: const Value('anticipo'),
            cashierId: actor.id,
          ));
      await _audit(actor, 'layaway_create', saleId,
          'total=$total; deposit=$depositCents');
      return LayawayCreateResult(
        saleId: saleId,
        folio: folio,
        totalCents: total,
        depositRequiredCents: depositRequired,
        balanceCents: total - depositCents,
      );
    });
  }

  /// Registra un abono. Devuelve el saldo restante.
  Future<int> addPayment({
    required Profile actor,
    required String saleId,
    required int amountCents,
    PaymentMethod method = PaymentMethod.cash,
  }) async {
    await _db.into(_db.payments).insert(PaymentsCompanion.insert(
          saleId: saleId,
          method: method,
          amountCents: amountCents,
          reference: const Value('abono'),
          cashierId: actor.id,
        ));
    return balance(saleId);
  }

  /// Liquida el apartado (requiere saldo 0): libera la reserva y descuenta del
  /// inventario; la venta pasa a `completed`.
  Future<void> settle({required Profile actor, required String saleId}) async {
    final bal = await balance(saleId);
    if (bal > 0) throw StateError('Saldo pendiente: $bal');
    await _db.transaction(() async {
      final sale =
          await (_db.select(_db.sales)..where((t) => t.id.equals(saleId))).getSingle();
      final lines = await (_db.select(_db.saleLines)
            ..where((t) => t.saleId.equals(saleId)))
          .get();
      for (final l in lines) {
        await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: l.variantId,
                locationId: sale.locationId,
                qty: -l.qty, // libera reserva
                type: MovementType.release,
                userId: Value(actor.id),
                referenceType: const Value('layaway'),
                referenceId: Value(saleId)));
        await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: l.variantId,
                locationId: sale.locationId,
                qty: -l.qty, // sale de existencia
                type: MovementType.sale,
                userId: Value(actor.id),
                referenceType: const Value('layaway'),
                referenceId: Value(saleId)));
      }
      await (_db.update(_db.sales)..where((t) => t.id.equals(saleId)))
          .write(const SalesCompanion(status: Value(SaleStatus.completed)));
      await (_db.update(_db.layawayTerms)..where((t) => t.saleId.equals(saleId)))
          .write(const LayawayTermsCompanion(
              status: Value(LayawayStatus.completed)));
      await _audit(actor, 'layaway_settle', saleId, 'liquidado');
    });
  }

  /// Marca vencidos los apartados pasados de fecha: libera reservas y convierte
  /// lo pagado en nota de crédito (política Fase 0). Devuelve cuántos procesó.
  Future<int> expireOverdue({required Profile actor}) async {
    final now = DateTime.now();
    final terms = await (_db.select(_db.layawayTerms)
          ..where((t) =>
              t.status.equalsValue(LayawayStatus.active) &
              t.expiresAt.isSmallerThanValue(now)))
        .get();
    var count = 0;
    for (final term in terms) {
      await _db.transaction(() async {
        final sale = await (_db.select(_db.sales)
              ..where((t) => t.id.equals(term.saleId)))
            .getSingle();
        final lines = await (_db.select(_db.saleLines)
              ..where((t) => t.saleId.equals(term.saleId)))
            .get();
        for (final l in lines) {
          await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                  variantId: l.variantId,
                  locationId: sale.locationId,
                  qty: -l.qty, // libera reserva (vuelve a disponible)
                  type: MovementType.release,
                  userId: Value(actor.id),
                  reason: const Value('Apartado vencido'),
                  referenceType: const Value('layaway'),
                  referenceId: Value(term.saleId)));
        }
        final pays = await (_db.select(_db.payments)
              ..where((t) => t.saleId.equals(term.saleId)))
            .get();
        final paid = pays.fold<int>(0, (s, p) => s + p.amountCents);
        if (paid > 0) {
          await _db.into(_db.creditNotes).insert(CreditNotesCompanion.insert(
                customerId: Value(sale.customerId),
                originSaleId: Value(term.saleId),
                amountCents: paid,
                balanceCents: paid,
                status: CreditNoteStatus.active,
                expiresAt: Value(now.add(const Duration(days: 90))),
              ));
        }
        await (_db.update(_db.layawayTerms)
              ..where((t) => t.saleId.equals(term.saleId)))
            .write(const LayawayTermsCompanion(
                status: Value(LayawayStatus.expired)));
        await (_db.update(_db.sales)..where((t) => t.id.equals(term.saleId)))
            .write(const SalesCompanion(status: Value(SaleStatus.cancelled)));
        await _audit(actor, 'layaway_expire', term.saleId,
            'creditoAFavor=$paid');
      });
      count++;
    }
    return count;
  }

  Future<List<LayawaySummary>> activeLayaways(int locationId) async {
    final rows = await (_db.select(_db.sales).join([
      innerJoin(_db.layawayTerms,
          _db.layawayTerms.saleId.equalsExp(_db.sales.id)),
    ])
          ..where(_db.sales.status.equalsValue(SaleStatus.layaway) &
              _db.sales.locationId.equals(locationId))
          ..orderBy([OrderingTerm.asc(_db.layawayTerms.expiresAt)]))
        .get();
    final out = <LayawaySummary>[];
    for (final r in rows) {
      final sale = r.readTable(_db.sales);
      final terms = r.readTable(_db.layawayTerms);
      String? customerName;
      if (sale.customerId != null) {
        final c = await (_db.select(_db.customers)
              ..where((t) => t.id.equals(sale.customerId!)))
            .getSingleOrNull();
        customerName = c?.name;
      }
      out.add(LayawaySummary(sale, terms, customerName, await balance(sale.id)));
    }
    return out;
  }

  Future<List<SaleLine>> linesOf(String saleId) =>
      (_db.select(_db.saleLines)..where((t) => t.saleId.equals(saleId))).get();

  Future<List<Payment>> paymentsOf(String saleId) =>
      (_db.select(_db.payments)..where((t) => t.saleId.equals(saleId))).get();

  Future<String> _takeFolio() async {
    final prefix = await _db.devicePrefix();
    final current = await (_db.select(_db.folioSequences)
          ..where((t) => t.prefix.equals(prefix)))
        .getSingleOrNull();
    final next = (current?.lastValue ?? 0) + 1;
    await _db.into(_db.folioSequences).insertOnConflictUpdate(
        FolioSequencesCompanion.insert(prefix: prefix, lastValue: Value(next)));
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }

  Future<void> _audit(
          Profile actor, String action, String saleId, String detail) =>
      _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: 'sale',
            entityId: Value(saleId),
            detail: Value(detail),
          ));
}
