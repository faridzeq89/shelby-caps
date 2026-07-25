import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/money.dart';
import '../local/database.dart';

/// Una línea que entra al cobro (precio ya congelado al momento de agregar).
class CheckoutLine {
  const CheckoutLine({
    required this.product,
    required this.variant,
    required this.qty,
    required this.unitPriceCents,
  });

  final Product product;
  final Variant variant;
  final int qty;
  final int unitPriceCents;
}

class CheckoutResult {
  const CheckoutResult({
    required this.saleId,
    required this.folio,
    required this.totalCents,
    required this.changeCents,
  });

  final String saleId;
  final String folio;
  final int totalCents;
  final int changeCents;
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
    required PaymentMethod method,
    required int amountTenderedCents,
    int? customerId,
    int? salespersonId,
  }) async {
    assert(lines.isNotEmpty, 'No se puede cobrar un carrito vacío');

    // Cálculo de totales (IVA incluido, desglosado por línea según su producto).
    var subtotal = 0, tax = 0, total = 0;
    final calc = <(_LineTotals, CheckoutLine)>[];
    for (final l in lines) {
      final lineTotal = l.unitPriceCents * l.qty;
      final bd = taxIncludedBreakdown(lineTotal, l.product.taxRateBps);
      calc.add((_LineTotals(lineTotal, bd.taxCents), l));
      total += lineTotal;
      tax += bd.taxCents;
      subtotal += bd.baseCents;
    }

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
              taxCents: tax,
              totalCents: total,
            ),
          );

      for (final (totals, line) in calc) {
        await _db.into(_db.saleLines).insert(
              SaleLinesCompanion.insert(
                saleId: saleId,
                variantId: line.variant.id,
                qty: line.qty,
                unitPriceCents: line.unitPriceCents,
                taxCents: totals.tax,
                lineTotalCents: totals.total,
              ),
            );
        await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                variantId: line.variant.id,
                locationId: locationId,
                qty: -line.qty, // salida
                type: MovementType.sale,
                userId: Value(cashier.id),
                referenceType: const Value('sale'),
                referenceId: Value(saleId),
              ),
            );
      }

      await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              saleId: saleId,
              method: method,
              amountCents: total,
              cashierId: cashier.id,
            ),
          );

      return CheckoutResult(
        saleId: saleId,
        folio: folio,
        totalCents: total,
        changeCents: amountTenderedCents - total,
      );
    });
  }

  Future<String> _devicePrefix() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals('device_prefix')))
        .getSingleOrNull();
    return row?.value ?? 'T1';
  }

  /// Folio dentro de la misma transacción del cobro (evita transacción anidada).
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

class _LineTotals {
  const _LineTotals(this.total, this.tax);
  final int total;
  final int tax;
}
