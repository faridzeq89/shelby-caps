import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../local/database.dart';
import 'sales_repository.dart' show CheckoutLine;

enum RefundMethod { cash, creditNote }

/// Una línea a devolver (apunta a la línea original de la venta).
class ReturnItem {
  const ReturnItem(this.line, this.qty, {this.damaged = false});
  final SaleLine line;
  final int qty;
  final bool damaged;
}

/// Línea original con lo que aún se puede devolver.
class ReturnableLine {
  const ReturnableLine(this.line, this.product, this.variant, this.returnable);
  final SaleLine line;
  final Product product;
  final Variant variant;
  final int returnable;
}

class ReturnResult {
  const ReturnResult({
    required this.returnSaleId,
    required this.folio,
    required this.refundCents,
    this.creditNoteId,
  });
  final String returnSaleId;
  final String folio;
  final int refundCents;
  final int? creditNoteId;
}

class ExchangeResult {
  const ExchangeResult({
    required this.returnSaleId,
    required this.newSaleId,
    required this.newFolio,
    required this.differenceCents, // >0 cobra al cliente, <0 a favor del cliente
    required this.cashCollectedCents,
    required this.changeCents,
    this.creditNoteId,
  });
  final String returnSaleId;
  final String newSaleId;
  final String newFolio;
  final int differenceCents;
  final int cashCollectedCents;
  final int changeCents;
  final int? creditNoteId;
}

/// Devoluciones y cambios. Una devolución es una venta con líneas de cantidad
/// negativa que apuntan a la línea original; un cambio es devolución + venta
/// nueva en una sola transacción.
class ReturnsRepository {
  ReturnsRepository(this._db);
  final AppDatabase _db;

  static const returnWindowDays = 15;
  static const _uuid = Uuid();

  Future<Sale?> findByFolio(String folio) => (_db.select(_db.sales)
        ..where((t) => t.folio.equals(folio.trim())))
      .getSingleOrNull();

  Future<int> alreadyReturned(int originalLineId) async {
    final rows = await (_db.select(_db.saleLines)
          ..where((t) => t.originalSaleLineId.equals(originalLineId)))
        .get();
    return rows.fold<int>(0, (s, l) => s + l.qty.abs());
  }

  /// Líneas originales de la venta con lo que todavía es devolvible.
  Future<List<ReturnableLine>> returnableLines(String saleId) async {
    final lines = await (_db.select(_db.saleLines)
          ..where((t) => t.saleId.equals(saleId) & t.qty.isBiggerThanValue(0)))
        .get();
    final out = <ReturnableLine>[];
    for (final l in lines) {
      final returned = await alreadyReturned(l.id);
      final variant = await (_db.select(_db.variants)
            ..where((t) => t.id.equals(l.variantId)))
          .getSingle();
      final product = await (_db.select(_db.products)
            ..where((t) => t.id.equals(variant.productId)))
          .getSingle();
      out.add(ReturnableLine(l, product, variant, l.qty - returned));
    }
    return out;
  }

  int _unitRefund(SaleLine l) => (l.lineTotalCents / l.qty).round();

  void _validate(Sale sale, List<ReturnItem> items) {
    final age = DateTime.now().difference(sale.createdAt).inDays;
    if (age > returnWindowDays) {
      throw StateError(
          'Fuera del plazo de devolución ($returnWindowDays días)');
    }
    if (items.isEmpty) throw ArgumentError('Nada por devolver');
  }

  Future<_Product> _productOf(int variantId) async {
    final v = await (_db.select(_db.variants)
          ..where((t) => t.id.equals(variantId)))
        .getSingle();
    final p = await (_db.select(_db.products)
          ..where((t) => t.id.equals(v.productId)))
        .getSingle();
    return _Product(p.taxRateBps);
  }

  // --------------------------------------------------------------------------
  // Devolución (reembolso)
  // --------------------------------------------------------------------------
  Future<ReturnResult> processReturn({
    required Profile actor,
    required Sale sale,
    required List<ReturnItem> items,
    required RefundMethod method,
    int? customerId,
    Profile? authorizedBy,
  }) async {
    _validate(sale, items);

    if (method == RefundMethod.cash &&
        !Permissions.canAuthorizeDiscount(actor.role) &&
        authorizedBy == null) {
      throw PermissionException(
          'El reembolso en efectivo requiere autorización de gerente');
    }

    for (final it in items) {
      final returned = await alreadyReturned(it.line.id);
      if (it.qty <= 0 || it.qty > it.line.qty - returned) {
        throw ArgumentError('Cantidad a devolver inválida en línea ${it.line.id}');
      }
    }

    final saleId = _uuid.v4();

    return _db.transaction(() async {
      final refund = await _writeReturn(actor, sale, items, saleId);
      await _updateOriginalStatus(sale);

      int? creditNoteId;
      if (method == RefundMethod.cash) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              saleId: saleId,
              method: PaymentMethod.cash,
              amountCents: -refund, // salida de efectivo
              cashierId: actor.id,
            ));
      } else {
        creditNoteId = await _db.into(_db.creditNotes).insert(
              CreditNotesCompanion.insert(
                customerId: Value(customerId),
                originSaleId: Value(saleId),
                amountCents: refund,
                balanceCents: refund,
                status: CreditNoteStatus.active,
                expiresAt: Value(DateTime.now().add(const Duration(days: 90))),
              ),
            );
      }

      await _audit(actor, 'return', saleId,
          'refund=$refund; method=${method.name}; from=${sale.folio}');
      return ReturnResult(
        returnSaleId: saleId,
        folio: await _folioOf(saleId),
        refundCents: refund,
        creditNoteId: creditNoteId,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Cambio (devolución + venta nueva atómica)
  // --------------------------------------------------------------------------
  Future<ExchangeResult> processExchange({
    required Profile actor,
    required Sale sale,
    required List<ReturnItem> returnItems,
    required List<CheckoutLine> newLines,
    required int cashTenderedCents,
    int? customerId,
  }) async {
    _validate(sale, returnItems);
    if (newLines.isEmpty) throw ArgumentError('Un cambio necesita artículos nuevos');

    for (final it in returnItems) {
      final returned = await alreadyReturned(it.line.id);
      if (it.qty <= 0 || it.qty > it.line.qty - returned) {
        throw ArgumentError('Cantidad a devolver inválida');
      }
    }

    final returnSaleId = _uuid.v4();
    final newSaleId = _uuid.v4();

    return _db.transaction(() async {
      // 1) Devolución: crédito por lo devuelto.
      final refund = await _writeReturn(actor, sale, returnItems, returnSaleId);
      await _updateOriginalStatus(sale);

      // 2) Venta nueva.
      final newTotal =
          newLines.fold<int>(0, (s, l) => s + l.unitPriceCents * l.qty);
      final creditApplied = refund < newTotal ? refund : newTotal;
      final cashNeeded = newTotal - creditApplied;
      final remainingCredit = refund - creditApplied;
      final difference = newTotal - refund; // >0 cobra, <0 a favor

      if (cashNeeded > 0 && cashTenderedCents < cashNeeded) {
        throw ArgumentError('Efectivo insuficiente para la diferencia');
      }

      var subtotal = 0, tax = 0;
      final newFolio = await _takeFolio();
      await _db.into(_db.sales).insert(SalesCompanion.insert(
            id: newSaleId,
            folio: newFolio,
            locationId: sale.locationId,
            cashierId: actor.id,
            customerId: Value(customerId),
            status: SaleStatus.completed,
            subtotalCents: 0,
            taxCents: 0,
            totalCents: newTotal,
            notes: Value('Cambio de ${sale.folio}'),
          ));
      for (final l in newLines) {
        final lineTotal = l.unitPriceCents * l.qty;
        final bd = taxIncludedBreakdown(lineTotal, l.product.taxRateBps);
        subtotal += bd.baseCents;
        tax += bd.taxCents;
        await _db.into(_db.saleLines).insert(SaleLinesCompanion.insert(
              saleId: newSaleId,
              variantId: l.variant.id,
              qty: l.qty,
              unitPriceCents: l.unitPriceCents,
              taxCents: bd.taxCents,
              lineTotalCents: lineTotal,
            ));
        await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: l.variant.id,
                locationId: sale.locationId,
                qty: -l.qty,
                type: MovementType.sale,
                userId: Value(actor.id),
                referenceType: const Value('sale'),
                referenceId: Value(newSaleId)));
      }
      await (_db.update(_db.sales)..where((t) => t.id.equals(newSaleId)))
          .write(SalesCompanion(
              subtotalCents: Value(subtotal), taxCents: Value(tax)));

      // Pagos de la venta nueva: crédito de la devolución + efectivo.
      if (creditApplied > 0) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              saleId: newSaleId,
              method: PaymentMethod.creditNote,
              amountCents: creditApplied,
              reference: Value(returnSaleId),
              cashierId: actor.id,
            ));
      }
      if (cashNeeded > 0) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              saleId: newSaleId,
              method: PaymentMethod.cash,
              amountCents: cashNeeded,
              cashierId: actor.id,
            ));
      }

      // Crédito sobrante (si devolvió más de lo que se llevó).
      int? creditNoteId;
      if (remainingCredit > 0) {
        creditNoteId = await _db.into(_db.creditNotes).insert(
            CreditNotesCompanion.insert(
                customerId: Value(customerId),
                originSaleId: Value(returnSaleId),
                amountCents: remainingCredit,
                balanceCents: remainingCredit,
                status: CreditNoteStatus.active,
                expiresAt:
                    Value(DateTime.now().add(const Duration(days: 90)))));
      }

      await _audit(actor, 'exchange', newSaleId,
          'from=${sale.folio}; refund=$refund; newTotal=$newTotal; diff=$difference');

      return ExchangeResult(
        returnSaleId: returnSaleId,
        newSaleId: newSaleId,
        newFolio: newFolio,
        differenceCents: difference,
        cashCollectedCents: cashNeeded,
        changeCents: cashNeeded > 0 ? cashTenderedCents - cashNeeded : 0,
        creditNoteId: creditNoteId,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Internos (asumen estar dentro de una transacción)
  // --------------------------------------------------------------------------

  /// Escribe la venta-devolución (líneas negativas + stock) y devuelve el monto
  /// reembolsado.
  Future<int> _writeReturn(
      Profile actor, Sale sale, List<ReturnItem> items, String returnSaleId) async {
    var refund = 0, refundTax = 0, refundSubtotal = 0;
    final calc = <(ReturnItem, int, int)>[]; // item, lineRefund, lineTax
    for (final it in items) {
      final unit = _unitRefund(it.line);
      final lineRefund = unit * it.qty;
      final prod = await _productOf(it.line.variantId);
      final bd = taxIncludedBreakdown(lineRefund, prod.taxRateBps);
      refund += lineRefund;
      refundTax += bd.taxCents;
      refundSubtotal += bd.baseCents;
      calc.add((it, lineRefund, bd.taxCents));
    }

    final fullyReturned = await _isFullyReturnedAfter(sale, items);
    final folio = await _takeFolio();
    await _db.into(_db.sales).insert(SalesCompanion.insert(
          id: returnSaleId,
          folio: folio,
          locationId: sale.locationId,
          cashierId: actor.id,
          status: fullyReturned ? SaleStatus.returned : SaleStatus.partialReturn,
          subtotalCents: -refundSubtotal,
          taxCents: -refundTax,
          totalCents: -refund,
          notes: Value('Devolución de ${sale.folio}'),
        ));

    for (final (it, lineRefund, lineTax) in calc) {
      await _db.into(_db.saleLines).insert(SaleLinesCompanion.insert(
            saleId: returnSaleId,
            variantId: it.line.variantId,
            qty: -it.qty,
            unitPriceCents: _unitRefund(it.line),
            taxCents: -lineTax,
            lineTotalCents: -lineRefund,
            originalSaleLineId: Value(it.line.id),
          ));
      // Regresa a existencia; si viene dañada, se saca con un ajuste aparte.
      await _db.into(_db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
              variantId: it.line.variantId,
              locationId: sale.locationId,
              qty: it.qty,
              type: MovementType.returned,
              userId: Value(actor.id),
              referenceType: const Value('return'),
              referenceId: Value(returnSaleId)));
      if (it.damaged) {
        await _db.into(_db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
                variantId: it.line.variantId,
                locationId: sale.locationId,
                qty: -it.qty,
                type: MovementType.adjustment,
                userId: Value(actor.id),
                reason: const Value('Pieza dañada, no vuelve a stock vendible'),
                referenceType: const Value('return'),
                referenceId: Value(returnSaleId)));
      }
    }
    return refund;
  }

  Future<bool> _isFullyReturnedAfter(Sale sale, List<ReturnItem> items) async {
    final lines = await (_db.select(_db.saleLines)
          ..where((t) => t.saleId.equals(sale.id) & t.qty.isBiggerThanValue(0)))
        .get();
    final extra = <int, int>{};
    for (final it in items) {
      extra[it.line.id] = (extra[it.line.id] ?? 0) + it.qty;
    }
    for (final l in lines) {
      final already = await alreadyReturned(l.id);
      if (already + (extra[l.id] ?? 0) < l.qty) return false;
    }
    return true;
  }

  Future<void> _updateOriginalStatus(Sale sale) async {
    final full = await _isFullyReturnedAfter(sale, const []);
    await (_db.update(_db.sales)..where((t) => t.id.equals(sale.id))).write(
        SalesCompanion(
            status: Value(
                full ? SaleStatus.returned : SaleStatus.partialReturn)));
  }

  Future<String> _folioOf(String saleId) async {
    final s = await (_db.select(_db.sales)..where((t) => t.id.equals(saleId)))
        .getSingle();
    return s.folio;
  }

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

class _Product {
  const _Product(this.taxRateBps);
  final int taxRateBps;
}
