import 'package:drift/drift.dart';

import '../local/database.dart';

/// Reglas del programa de puntos. Configurables por `app_settings`; si no hay
/// valores, se usan los de fábrica.
class LoyaltyConfig {
  const LoyaltyConfig({
    required this.earnPerPeso,
    required this.redeemCentsPerPoint,
  });

  /// Puntos ganados por cada peso gastado (default 1 → $1 = 1 punto).
  final int earnPerPeso;

  /// Valor en centavos de cada punto al canjear (default 10 → 10 pts = $1).
  final int redeemCentsPerPoint;
}

/// Puntos de lealtad por cliente, sobre el ledger append-only
/// `loyalty_transactions`. El saldo es la suma de los puntos.
class LoyaltyRepository {
  LoyaltyRepository(this._db);
  final AppDatabase _db;

  static const defaultEarnPerPeso = 1;
  static const defaultRedeemCentsPerPoint = 10;

  Future<int> balance(int customerId) async {
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(points), 0) AS b FROM loyalty_transactions '
      'WHERE customer_id = ?',
      variables: [Variable.withInt(customerId)],
      readsFrom: {_db.loyaltyTransactions},
    ).getSingle();
    return row.read<int>('b');
  }

  Future<List<LoyaltyTransaction>> history(int customerId, {int limit = 100}) =>
      (_db.select(_db.loyaltyTransactions)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .get();

  Future<LoyaltyConfig> config() async {
    return LoyaltyConfig(
      earnPerPeso:
          int.tryParse(await _setting('loyalty_earn_per_peso') ?? '') ??
              defaultEarnPerPeso,
      redeemCentsPerPoint: int.tryParse(
              await _setting('loyalty_redeem_cents_per_point') ?? '') ??
          defaultRedeemCentsPerPoint,
    );
  }

  /// Guarda las reglas del programa (solo se llama desde Admin).
  Future<void> setConfig({
    required int earnPerPeso,
    required int redeemCentsPerPoint,
  }) async {
    if (earnPerPeso < 0 || redeemCentsPerPoint < 1) {
      throw ArgumentError('Valores de lealtad inválidos');
    }
    await _putSetting('loyalty_earn_per_peso', earnPerPeso.toString());
    await _putSetting(
        'loyalty_redeem_cents_per_point', redeemCentsPerPoint.toString());
  }

  Future<void> _putSetting(String key, String value) {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  /// Ajuste manual de puntos (regalo, corrección). Positivo suma, negativo resta.
  Future<void> adjust(int customerId, int points) {
    return _db.into(_db.loyaltyTransactions).insert(
          LoyaltyTransactionsCompanion.insert(
            customerId: customerId,
            points: points,
            type: LoyaltyType.adjust,
          ),
        );
  }

  Future<String?> _setting(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }
}
