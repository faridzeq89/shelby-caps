import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../local/database.dart';
import 'gift_card_repository.dart';
import 'loyalty_repository.dart';

/// Una línea que entra al cobro (precio ya congelado al momento de agregar).
class CheckoutLine {
  const CheckoutLine({
    required this.product,
    required this.variant,
    required this.qty,
    required this.unitPriceCents,
    this.lineDiscountCents = 0,
  });

  final Product product;
  final Variant variant;
  final int qty;
  final int unitPriceCents;

  /// Descuento aplicado SOLO a esta línea (además del descuento por venta).
  final int lineDiscountCents;

  int get grossCents => unitPriceCents * qty;

  /// Importe de la línea tras su propio descuento (antes del de venta).
  int get baseCents =>
      (grossCents - lineDiscountCents).clamp(0, grossCents);
}

/// Un pago que entra al cobro. Puede haber varios (pago dividido).
class PaymentInput {
  const PaymentInput(this.method, this.amountCents, {this.giftCardId});
  final PaymentMethod method;
  final int amountCents;

  /// Tarjeta de regalo a debitar cuando `method == giftCard`.
  final int? giftCardId;
}

class CheckoutResult {
  const CheckoutResult({
    required this.saleId,
    required this.folio,
    required this.grossCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.changeCents,
    this.earnedPoints = 0,
    this.redeemedPoints = 0,
  });

  final String saleId;
  final String folio;
  final int grossCents;
  final int discountCents;
  final int taxCents;
  final int totalCents; // neto (bruto - descuento)
  final int changeCents;
  final int earnedPoints; // puntos de lealtad ganados en esta venta
  final int redeemedPoints; // puntos canjeados como descuento
}

/// Registra ventas. El cobro es **una sola transacción**: venta + líneas + pago
/// + movimientos de inventario. Si algo falla, no queda nada a medias.
class SalesRepository {
  SalesRepository(this._db);
  final AppDatabase _db;

  static const _uuid = Uuid();

  Future<CheckoutResult> checkout({
    required Profile cashier,
    required int locationId,
    required List<CheckoutLine> lines,
    required List<PaymentInput> payments,
    int discountCents = 0,
    String? discountReason,
    int? customerId,
    int? salespersonId,
    int redeemPoints = 0,
    bool taxEnabled = false,
  }) async {
    assert(lines.isNotEmpty, 'No se puede cobrar un carrito vacío');
    if (redeemPoints > 0 && customerId == null) {
      throw ArgumentError('No se pueden canjear puntos sin cliente');
    }

    // Dos niveles de descuento:
    //  1) por línea (l.lineDiscountCents), aplicado antes del reparto;
    //  2) por venta (discountCents), repartido proporcional sobre lo que quede,
    //     para conservar el IVA por producto y que el total cuadre al centavo.
    final gross = lines.fold(0, (s, l) => s + l.grossCents);
    final baseSum = lines.fold(0, (s, l) => s + l.baseCents);
    // Canje de puntos: se aplica como descuento adicional (valor configurable).
    final loyaltyCfg = await LoyaltyRepository(_db).config();
    final redeemCents = redeemPoints * loyaltyCfg.redeemCentsPerPoint;
    final saleDiscount = (discountCents + redeemCents).clamp(0, baseSum);
    final net = baseSum - saleDiscount;
    final discount = gross - net; // descuento total (línea + venta + canje)

    var subtotal = 0, tax = 0;
    final lineRows = <SaleLinesCompanion>[];
    var allocated = 0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final isLast = i == lines.length - 1;
      final lineNet = isLast
          ? net - allocated
          : (baseSum == 0 ? 0 : (l.baseCents * net / baseSum).round());
      allocated += lineNet;
      // Con el IVA apagado (el negocio no factura) el precio es el precio: no
      // se desglosa nada y la venta se guarda con impuesto cero.
      final bd = taxIncludedBreakdown(
          lineNet, taxEnabled ? l.product.taxRateBps : 0);
      subtotal += bd.baseCents;
      tax += bd.taxCents;
      lineRows.add(SaleLinesCompanion.insert(
        saleId: '', // se rellena dentro de la transacción
        variantId: l.variant.id,
        qty: l.qty,
        unitPriceCents: l.unitPriceCents,
        discountCents: Value(l.grossCents - lineNet),
        taxCents: bd.taxCents,
        lineTotalCents: lineNet,
      ));
    }

    // Validación de pagos.
    final nonCash = payments
        .where((p) => p.method != PaymentMethod.cash)
        .fold(0, (s, p) => s + p.amountCents);
    final cashEntered = payments
        .where((p) => p.method == PaymentMethod.cash)
        .fold(0, (s, p) => s + p.amountCents);
    if (nonCash > net) {
      throw ArgumentError('Los pagos distintos a efectivo superan el total');
    }
    final cashApplied = net - nonCash;
    if (cashApplied > 0 && cashEntered < cashApplied) {
      throw ArgumentError('Efectivo insuficiente para cubrir el total');
    }
    final change = (cashEntered - cashApplied).clamp(0, cashEntered);

    final saleId = _uuid.v4();
    final prefix = await _devicePrefix();

    return _db.transaction(() async {
      final folio = await _nextFolio(prefix);

      await _db.into(_db.sales).insert(
            SalesCompanion.insert(
              id: saleId,
              folio: folio,
              locationId: locationId,
              cashierId: cashier.id,
              salespersonId: Value(salespersonId),
              customerId: Value(customerId),
              status: SaleStatus.completed,
              subtotalCents: subtotal,
              discountCents: Value(discount),
              taxCents: tax,
              totalCents: net,
              notes: Value(discount > 0 ? discountReason : null),
            ),
          );

      for (var i = 0; i < lineRows.length; i++) {
        await _db.into(_db.saleLines).insert(
              lineRows[i].copyWith(saleId: Value(saleId)),
            );
        // Los servicios (limpieza, personalización) NO manejan inventario: se
        // registra la venta pero no se descuenta stock.
        if (!lines[i].product.esServicio) {
          await _db.into(_db.inventoryMovements).insert(
                InventoryMovementsCompanion.insert(
                  variantId: lines[i].variant.id,
                  locationId: locationId,
                  qty: -lines[i].qty,
                  type: MovementType.sale,
                  userId: Value(cashier.id),
                  referenceType: const Value('sale'),
                  referenceId: Value(saleId),
                ),
              );
        }
      }

      // Pagos: los que no son efectivo tal cual; el efectivo, sólo lo aplicado
      // (el excedente es cambio, no ingreso).
      for (final p in payments.where((p) => p.method != PaymentMethod.cash)) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              saleId: saleId,
              method: p.method,
              amountCents: p.amountCents,
              cashierId: cashier.id,
            ));
      }

      // Canje de tarjetas de regalo, en la misma transacción (valida saldo).
      final giftRepo = GiftCardRepository(_db);
      for (final p in payments.where((p) => p.method == PaymentMethod.giftCard)) {
        if (p.giftCardId == null) {
          throw ArgumentError('Pago con tarjeta de regalo sin identificarla');
        }
        await giftRepo.redeem(
            cardId: p.giftCardId!, amountCents: p.amountCents, saleId: saleId);
      }
      if (cashApplied > 0) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
              saleId: saleId,
              method: PaymentMethod.cash,
              amountCents: cashApplied,
              cashierId: cashier.id,
            ));
      }

      if (discount > 0) {
        await _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
              userId: Value(cashier.id),
              action: 'sale_discount',
              entityType: 'sale',
              entityId: Value(saleId),
              detail: Value('discountCents=$discount; ${discountReason ?? ''}'),
            ));
      }

      // Lealtad: canje (si hay) y ganancia de puntos, sobre el neto pagado.
      var earnedPoints = 0;
      if (customerId != null) {
        if (redeemPoints > 0) {
          final balRow = await _db.customSelect(
            'SELECT COALESCE(SUM(points), 0) AS b FROM loyalty_transactions '
            'WHERE customer_id = ?',
            variables: [Variable.withInt(customerId)],
          ).getSingle();
          if (balRow.read<int>('b') < redeemPoints) {
            throw ArgumentError('Puntos insuficientes para canjear');
          }
          await _db.into(_db.loyaltyTransactions).insert(
                LoyaltyTransactionsCompanion.insert(
                  customerId: customerId,
                  saleId: Value(saleId),
                  points: -redeemPoints,
                  type: LoyaltyType.redeem,
                ),
              );
        }
        earnedPoints = net * loyaltyCfg.earnPerPeso ~/ 100;
        if (earnedPoints > 0) {
          await _db.into(_db.loyaltyTransactions).insert(
                LoyaltyTransactionsCompanion.insert(
                  customerId: customerId,
                  saleId: Value(saleId),
                  points: earnedPoints,
                  type: LoyaltyType.earn,
                ),
              );
        }
      }

      return CheckoutResult(
        saleId: saleId,
        folio: folio,
        grossCents: gross,
        discountCents: discount,
        taxCents: tax,
        totalCents: net,
        changeCents: change,
        earnedPoints: earnedPoints,
        redeemedPoints: redeemPoints,
      );
    });
  }

  /// Vende (emite) una tarjeta de regalo: crea la tarjeta con su saldo y una
  /// venta sin líneas con el pago, para que el dinero entre al corte de caja.
  /// Todo en una sola transacción.
  Future<({GiftCard card, String folio, int changeCents})> sellGiftCard({
    required Profile cashier,
    required int locationId,
    required int amountCents,
    required List<PaymentInput> payments,
    int? customerId,
  }) async {
    if (amountCents <= 0) throw ArgumentError('El monto debe ser mayor a 0');
    final nonCash = payments
        .where((p) => p.method != PaymentMethod.cash)
        .fold(0, (s, p) => s + p.amountCents);
    if (nonCash > amountCents) {
      throw ArgumentError('Los pagos distintos a efectivo superan el monto');
    }
    final cashApplied = amountCents - nonCash;
    final cashEntered = payments
        .where((p) => p.method == PaymentMethod.cash)
        .fold(0, (s, p) => s + p.amountCents);
    if (cashApplied > 0 && cashEntered < cashApplied) {
      throw ArgumentError('Efectivo insuficiente');
    }
    final change = (cashEntered - cashApplied).clamp(0, cashEntered);
    final saleId = _uuid.v4();
    final prefix = await _devicePrefix();

    return _db.transaction(() async {
      final folio = await _nextFolio(prefix);
      await _db.into(_db.sales).insert(SalesCompanion.insert(
            id: saleId,
            folio: folio,
            locationId: locationId,
            cashierId: cashier.id,
            customerId: Value(customerId),
            status: SaleStatus.completed,
            subtotalCents: amountCents,
            taxCents: 0,
            totalCents: amountCents,
            notes: const Value('Venta de tarjeta de regalo'),
          ));
      for (final p in payments.where((p) => p.method != PaymentMethod.cash)) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: saleId,
            method: p.method,
            amountCents: p.amountCents,
            cashierId: cashier.id));
      }
      if (cashApplied > 0) {
        await _db.into(_db.payments).insert(PaymentsCompanion.insert(
            saleId: saleId,
            method: PaymentMethod.cash,
            amountCents: cashApplied,
            cashierId: cashier.id));
      }
      final card = await GiftCardRepository(_db).issue(
          initialCents: amountCents, customerId: customerId, saleId: saleId);
      return (card: card, folio: folio, changeCents: change);
    });
  }

  /// Cancela una venta del día: no borra la fila (queda `cancelled`), devuelve
  /// el stock con movimientos `returned` y lo registra en `audit_log`.
  Future<void> cancelSale({
    required Profile actor,
    required String saleId,
    String? reason,
  }) async {
    if (!Permissions.canCancelSale(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede cancelar ventas');
    }
    await _db.transaction(() async {
      final sale = await (_db.select(_db.sales)
            ..where((t) => t.id.equals(saleId)))
          .getSingle();
      if (sale.status == SaleStatus.cancelled) return;

      final saleLines = await (_db.select(_db.saleLines)
            ..where((t) => t.saleId.equals(saleId)))
          .get();
      for (final l in saleLines) {
        await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                variantId: l.variantId,
                locationId: sale.locationId,
                qty: l.qty.abs(), // regresa a existencia
                type: MovementType.returned,
                userId: Value(actor.id),
                referenceType: const Value('cancel'),
                referenceId: Value(saleId),
                reason: const Value('Cancelación de venta'),
              ),
            );
      }

      await (_db.update(_db.sales)..where((t) => t.id.equals(saleId)))
          .write(const SalesCompanion(status: Value(SaleStatus.cancelled)));

      await _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: 'cancel_sale',
            entityType: 'sale',
            entityId: Value(saleId),
            detail: Value(reason ?? ''),
          ));
    });
  }

  Future<String> _devicePrefix() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals('device_prefix')))
        .getSingleOrNull();
    return row?.value ?? 'T1';
  }

  Future<String> _nextFolio(String prefix) async {
    final current = await (_db.select(_db.folioSequences)
          ..where((t) => t.prefix.equals(prefix)))
        .getSingleOrNull();
    final next = (current?.lastValue ?? 0) + 1;
    await _db.into(_db.folioSequences).insertOnConflictUpdate(
          FolioSequencesCompanion.insert(prefix: prefix, lastValue: Value(next)),
        );
    return '$prefix-${next.toString().padLeft(6, '0')}';
  }
}
