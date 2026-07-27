import 'dart:math';

import 'package:drift/drift.dart';

import '../local/database.dart';

/// Tarjeta con su saldo calculado (suma del ledger).
class GiftCardWithBalance {
  const GiftCardWithBalance(this.card, this.balanceCents);
  final GiftCard card;
  final int balanceCents;
}

/// Tarjetas de regalo (saldo prepagado) sobre el ledger append-only
/// `gift_card_transactions`. El saldo es la suma de los montos.
class GiftCardRepository {
  GiftCardRepository(this._db);
  final AppDatabase _db;

  static final _rnd = Random.secure();

  /// Código único generado por la app: `GR` + 12 dígitos.
  Future<String> _newCode() async {
    for (var i = 0; i < 30; i++) {
      final digits = List.generate(12, (_) => _rnd.nextInt(10)).join();
      final code = 'GR$digits';
      final exists = await (_db.select(_db.giftCards)
            ..where((t) => t.code.equals(code)))
          .getSingleOrNull();
      if (exists == null) return code;
    }
    throw StateError('No se pudo generar un código único');
  }

  /// Emite una tarjeta con [initialCents] de saldo. Devuelve la tarjeta creada.
  /// No abre transacción propia: si el que llama ya está en una (p. ej. la venta
  /// de la tarjeta), participa en ella para ser atómico.
  Future<GiftCard> issue({
    required int initialCents,
    int? customerId,
    String? saleId,
  }) async {
    if (initialCents <= 0) throw ArgumentError('El monto debe ser mayor a 0');
    final code = await _newCode();
    final id = await _db.into(_db.giftCards).insert(
          GiftCardsCompanion.insert(code: code, customerId: Value(customerId)),
        );
    await _db.into(_db.giftCardTransactions).insert(
          GiftCardTransactionsCompanion.insert(
            cardId: id,
            amountCents: initialCents,
            type: GiftCardTxType.issue,
            saleId: Value(saleId),
          ),
        );
    return (_db.select(_db.giftCards)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<int> balance(int cardId) async {
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(amount_cents), 0) AS b '
      'FROM gift_card_transactions WHERE card_id = ?',
      variables: [Variable.withInt(cardId)],
      readsFrom: {_db.giftCardTransactions},
    ).getSingle();
    return row.read<int>('b');
  }

  /// Busca por código (para pagar o consultar). Null si no existe.
  Future<GiftCardWithBalance?> findByCode(String code) async {
    final card = await (_db.select(_db.giftCards)
          ..where((t) => t.code.equals(code.trim())))
        .getSingleOrNull();
    if (card == null) return null;
    return GiftCardWithBalance(card, await balance(card.id));
  }

  Future<List<GiftCardTransaction>> history(int cardId) =>
      (_db.select(_db.giftCardTransactions)
            ..where((t) => t.cardId.equals(cardId))
            ..orderBy([
              (t) =>
                  OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
            ]))
          .get();

  /// Registra un canje (−). Pensado para llamarse DENTRO de la transacción del
  /// checkout; valida saldo y lanza si es insuficiente.
  Future<void> redeem({
    required int cardId,
    required int amountCents,
    String? saleId,
  }) async {
    if (amountCents <= 0) throw ArgumentError('Monto de canje inválido');
    final bal = await balance(cardId);
    if (bal < amountCents) {
      throw ArgumentError('Saldo insuficiente en la tarjeta de regalo');
    }
    await _db.into(_db.giftCardTransactions).insert(
          GiftCardTransactionsCompanion.insert(
            cardId: cardId,
            amountCents: -amountCents,
            type: GiftCardTxType.redeem,
            saleId: Value(saleId),
          ),
        );
  }

  /// Recarga o corrección manual de saldo (+ suma, − resta).
  Future<void> adjust(int cardId, int amountCents) {
    return _db.into(_db.giftCardTransactions).insert(
          GiftCardTransactionsCompanion.insert(
            cardId: cardId,
            amountCents: amountCents,
            type: GiftCardTxType.adjust,
          ),
        );
  }
}
