import 'package:drift/drift.dart';

import '../local/database.dart';

/// Resumen en vivo de un turno de caja.
class CashSessionSummary {
  const CashSessionSummary({
    required this.openingFloatCents,
    required this.cashSalesCents,
    required this.cardSalesCents,
    required this.otherSalesCents,
    required this.depositsCents,
    required this.withdrawalsCents,
  });

  final int openingFloatCents;
  final int cashSalesCents;
  final int cardSalesCents;
  final int otherSalesCents;
  final int depositsCents;
  final int withdrawalsCents;

  /// Lo que debería haber en el cajón al cerrar.
  int get expectedCashCents =>
      openingFloatCents + cashSalesCents + depositsCents - withdrawalsCents;
}

/// Corte de caja: apertura con fondo, retiros/depósitos y cierre con arqueo.
class CashSessionRepository {
  CashSessionRepository(this._db);
  final AppDatabase _db;

  Future<CashSession?> currentOpen(int locationId) {
    return (_db.select(_db.cashSessions)
          ..where((t) =>
              t.locationId.equals(locationId) &
              t.status.equalsValue(CashSessionStatus.open))
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> open({
    required Profile actor,
    required int locationId,
    required int openingFloatCents,
  }) async {
    if (await currentOpen(locationId) != null) {
      throw StateError('Ya hay una caja abierta en esta ubicación');
    }
    return _db.into(_db.cashSessions).insert(CashSessionsCompanion.insert(
          locationId: locationId,
          openingFloatCents: openingFloatCents,
          openedBy: actor.id,
          status: CashSessionStatus.open,
        ));
  }

  Future<int> recordCash({
    required Profile actor,
    required CashSession session,
    required CashMovementKind kind,
    required int amountCents,
    String? reason,
  }) {
    return _db.into(_db.cashMovements).insert(CashMovementsCompanion.insert(
          sessionId: session.id,
          kind: kind,
          amountCents: amountCents,
          userId: Value(actor.id),
          reason: Value(reason),
        ));
  }

  /// Ventas del turno (completadas): entre la apertura y ahora (o el cierre).
  Future<List<Sale>> salesOfSession(CashSession session) {
    final until = session.closedAt ?? DateTime.now();
    return (_db.select(_db.sales)
          ..where((t) =>
              t.locationId.equals(session.locationId) &
              t.createdAt.isBiggerOrEqualValue(session.openedAt) &
              t.createdAt.isSmallerOrEqualValue(until))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<CashSessionSummary> summary(CashSession session) async {
    final until = session.closedAt ?? DateTime.now();

    // Pagos de ventas completadas del turno, por método.
    final rows = await (_db.select(_db.payments).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.payments.saleId)),
    ])
          ..where(_db.sales.status.equalsValue(SaleStatus.completed) &
              _db.sales.createdAt.isBiggerOrEqualValue(session.openedAt) &
              _db.sales.createdAt.isSmallerOrEqualValue(until) &
              _db.sales.locationId.equals(session.locationId)))
        .get();

    var cash = 0, card = 0, other = 0;
    for (final r in rows) {
      final p = r.readTable(_db.payments);
      switch (p.method) {
        case PaymentMethod.cash:
          cash += p.amountCents;
        case PaymentMethod.card:
          card += p.amountCents;
        case PaymentMethod.transfer:
        case PaymentMethod.creditNote:
          other += p.amountCents;
      }
    }

    final movements = await (_db.select(_db.cashMovements)
          ..where((t) => t.sessionId.equals(session.id)))
        .get();
    var deposits = 0, withdrawals = 0;
    for (final m in movements) {
      if (m.kind == CashMovementKind.deposit) {
        deposits += m.amountCents;
      } else {
        withdrawals += m.amountCents;
      }
    }

    return CashSessionSummary(
      openingFloatCents: session.openingFloatCents,
      cashSalesCents: cash,
      cardSalesCents: card,
      otherSalesCents: other,
      depositsCents: deposits,
      withdrawalsCents: withdrawals,
    );
  }

  /// Cierra el turno: guarda conteo declarado, esperado y diferencia.
  Future<CashSession> close({
    required Profile actor,
    required CashSession session,
    required int countedCents,
  }) async {
    final sum = await summary(session);
    final expected = sum.expectedCashCents;
    await (_db.update(_db.cashSessions)..where((t) => t.id.equals(session.id)))
        .write(CashSessionsCompanion(
      closingCountCents: Value(countedCents),
      expectedCents: Value(expected),
      varianceCents: Value(countedCents - expected),
      closedBy: Value(actor.id),
      closedAt: Value(DateTime.now()),
      status: const Value(CashSessionStatus.closed),
    ));
    return (_db.select(_db.cashSessions)..where((t) => t.id.equals(session.id)))
        .getSingle();
  }
}
