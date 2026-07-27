import 'package:drift/drift.dart';

import '../local/database.dart';

/// Resumen de ventas de un periodo. Los montos ya vienen con IVA incluido
/// (dinero en centavos). Las devoluciones se reportan aparte, en positivo.
class PeriodSummary {
  const PeriodSummary({
    required this.salesCount,
    required this.grossCents,
    required this.discountCents,
    required this.taxCents,
    required this.netCents,
    required this.itemsSold,
    required this.returnsCount,
    required this.returnsCents,
  });
  final int salesCount;
  final int grossCents; // suma de total de ventas completadas
  final int discountCents;
  final int taxCents;
  final int netCents; // gross - devoluciones
  final int itemsSold; // piezas netas (ventas - devoluciones)
  final int returnsCount;
  final int returnsCents; // monto devuelto, en positivo
}

/// Unidades y dinero por variante (para top de ventas y desglose talla/color).
class VariantSales {
  const VariantSales({
    required this.productName,
    required this.size,
    required this.color,
    required this.sku,
    required this.unitsSold,
    required this.revenueCents,
  });
  final String productName;
  final String? size;
  final String? color;
  final String sku;
  final int unitsSold;
  final int revenueCents;

  String get label {
    final tc = '${size ?? ''} ${color ?? ''}'.trim();
    return tc.isEmpty ? productName : '$productName ($tc)';
  }
}

/// Margen por producto (último costo). margen = ingreso − costo de lo vendido.
class ProductMargin {
  const ProductMargin({
    required this.productName,
    required this.unitsSold,
    required this.revenueCents,
    required this.costCents,
  });
  final String productName;
  final int unitsSold;
  final int revenueCents;
  final int costCents;
  int get marginCents => revenueCents - costCents;
  double get marginPct => revenueCents == 0 ? 0 : marginCents / revenueCents * 100;
}

/// Inventario muerto: existencia sin venta en N días.
class DeadStockItem {
  const DeadStockItem({
    required this.productName,
    required this.sku,
    required this.size,
    required this.color,
    required this.onHand,
    required this.lastSold,
  });
  final String productName;
  final String sku;
  final String? size;
  final String? color;
  final int onHand;
  final DateTime? lastSold;
}

/// Diferencias de caja por cajero (arqueos históricos).
class CashierVariance {
  const CashierVariance({
    required this.name,
    required this.sessions,
    required this.totalVarianceCents,
  });
  final String name;
  final int sessions;
  final int totalVarianceCents; // negativo = faltó efectivo
}

/// Tasa de devolución por producto.
class ReturnRate {
  const ReturnRate({
    required this.productName,
    required this.sold,
    required this.returned,
  });
  final String productName;
  final int sold;
  final int returned;
  double get rate => sold == 0 ? 0 : returned / sold * 100;
}

/// Ventas atribuidas a un vendedor (hueco #13). Cae al cajero si no hubo
/// vendedor asignado.
class SalespersonSales {
  const SalespersonSales({
    required this.name,
    required this.salesCount,
    required this.revenueCents,
  });
  final String name;
  final int salesCount;
  final int revenueCents;
}

/// Tipo de recomendación (ordena la prioridad al mostrarlas).
enum RecoKind { restock, promo, overstock }

/// Una recomendación accionable derivada de ventas + existencia.
class Recommendation {
  const Recommendation({
    required this.productName,
    required this.sku,
    required this.action,
    required this.reason,
    required this.kind,
  });
  final String productName;
  final String sku;
  final String action;
  final String reason;
  final RecoKind kind;
}

/// Consultas de reporte (solo lectura sobre el ledger y las ventas). No muta
/// nada. Los estados de venta se guardan como el NOMBRE del enum
/// (`completed`, `returned`, `partialReturn`, ...).
class ReportsRepository {
  ReportsRepository(this._db);
  final AppDatabase _db;

  // Estados que cuentan como venta neta (la devolución trae total negativo).
  static const _soldStatuses = "('completed','returned','partialReturn')";
  static const _returnStatuses = "('returned','partialReturn')";

  Variable _d(DateTime t) => Variable.withDateTime(t);

  // ---------------------------------------------------------------------------
  // Recomendaciones accionables (reglas sobre ventas de 30 días + existencia)
  // ---------------------------------------------------------------------------
  Future<List<Recommendation>> recommendations() async {
    final now = DateTime.now();
    final cut30 = now.subtract(const Duration(days: 30));
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, v.sku AS sku, '
      'COALESCE(vs.on_hand, 0) AS on_hand, COALESCE(vs.reserved, 0) AS reserved, '
      '(SELECT COALESCE(SUM(sl.qty), 0) FROM sale_lines sl '
      '   JOIN sales s ON s.id = sl.sale_id '
      "   WHERE sl.variant_id = v.id AND sl.qty > 0 AND s.status IN $_soldStatuses "
      '   AND s.created_at >= ?) AS sold30, '
      '(SELECT MAX(s.created_at) FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id '
      "   WHERE sl.variant_id = v.id AND sl.qty > 0 AND s.status IN $_soldStatuses) AS last_sold "
      'FROM variants v JOIN products p ON p.id = v.product_id '
      'LEFT JOIN variant_stock vs ON vs.variant_id = v.id '
      'WHERE v.active = 1',
      variables: [_d(cut30)],
      readsFrom: {_db.variants, _db.products, _db.sales, _db.saleLines, _db.inventoryMovements},
    ).get();

    final out = <Recommendation>[];
    for (final r in rows) {
      final name = r.read<String>('pname');
      final sku = r.read<String>('sku');
      final available = r.read<int>('on_hand') - r.read<int>('reserved');
      final sold30 = r.read<int>('sold30');
      final lastSold = r.read<DateTime?>('last_sold');
      final days = lastSold == null ? null : now.difference(lastSold).inDays;

      // 1) Reabastecer: se vende rápido y queda poco (menos de ~1 mes de cobertura).
      if (sold30 >= 3 && available >= 0 && available <= sold30) {
        out.add(Recommendation(
          productName: name,
          sku: sku,
          kind: RecoKind.restock,
          action: 'Reabastecer',
          reason:
              'Vendió $sold30 en 30 días y quedan $available. Conviene subir inventario.',
        ));
        continue;
      }
      // 2) Poner en oferta: con existencia y sin venta reciente (45+ días o nunca).
      if (available > 0 && (lastSold == null || (days ?? 99999) >= 45)) {
        out.add(Recommendation(
          productName: name,
          sku: sku,
          kind: RecoKind.promo,
          action: 'Poner en oferta',
          reason: lastSold == null
              ? 'Nunca se ha vendido y hay $available en existencia.'
              : 'Sin venta en $days días, con $available en existencia.',
        ));
        continue;
      }
      // 3) Descuento por sobre-stock lento: mucha existencia, venta lenta.
      if (available >= 10 && sold30 >= 1 && sold30 <= 2) {
        out.add(Recommendation(
          productName: name,
          sku: sku,
          kind: RecoKind.overstock,
          action: 'Considerar descuento',
          reason: 'Existencia alta ($available) y venta lenta ($sold30 en 30 días).',
        ));
      }
    }
    out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    // Tope para no pintar cientos de filas de golpe (traba la UI).
    return out.length > 80 ? out.sublist(0, 80) : out;
  }

  // ---------------------------------------------------------------------------
  // Resumen de periodo (día/semana/mes) — con soporte de comparativo
  // ---------------------------------------------------------------------------
  Future<PeriodSummary> periodSummary(DateTime from, DateTime to) async {
    final row = await _db.customSelect(
      'SELECT '
      "COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0) AS n, "
      "COALESCE(SUM(CASE WHEN status = 'completed' THEN total_cents ELSE 0 END), 0) AS gross, "
      "COALESCE(SUM(CASE WHEN status = 'completed' THEN discount_cents ELSE 0 END), 0) AS disc, "
      'COALESCE(SUM(total_cents), 0) AS net, '
      'COALESCE(SUM(tax_cents), 0) AS tax, '
      "COALESCE(SUM(CASE WHEN status IN $_returnStatuses THEN 1 ELSE 0 END), 0) AS rn, "
      "COALESCE(-SUM(CASE WHEN status IN $_returnStatuses THEN total_cents ELSE 0 END), 0) AS ret "
      'FROM sales '
      'WHERE status IN $_soldStatuses AND created_at >= ? AND created_at < ?',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales},
    ).getSingle();

    final itemsRow = await _db.customSelect(
      'SELECT COALESCE(SUM(sl.qty), 0) AS units '
      'FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id '
      'WHERE s.status IN $_soldStatuses AND s.created_at >= ? AND s.created_at < ?',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales, _db.saleLines},
    ).getSingle();

    return PeriodSummary(
      salesCount: row.read<int>('n'),
      grossCents: row.read<int>('gross'),
      discountCents: row.read<int>('disc'),
      taxCents: row.read<int>('tax'),
      netCents: row.read<int>('net'),
      itemsSold: itemsRow.read<int>('units'),
      returnsCount: row.read<int>('rn'),
      returnsCents: row.read<int>('ret'),
    );
  }

  // ---------------------------------------------------------------------------
  // Ventas por variante (top y desglose talla/color)
  // ---------------------------------------------------------------------------
  Future<List<VariantSales>> variantSales(DateTime from, DateTime to,
      {int? limit, bool ascending = false}) async {
    final order = ascending ? 'ASC' : 'DESC';
    final lim = limit == null ? '' : 'LIMIT $limit';
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, v.size AS size, v.color AS color, v.sku AS sku, '
      'COALESCE(SUM(sl.qty), 0) AS units, COALESCE(SUM(sl.line_total_cents), 0) AS rev '
      'FROM sale_lines sl '
      'JOIN sales s ON s.id = sl.sale_id '
      'JOIN variants v ON v.id = sl.variant_id '
      'JOIN products p ON p.id = v.product_id '
      'WHERE s.status IN $_soldStatuses AND s.created_at >= ? AND s.created_at < ? '
      'GROUP BY v.id HAVING units <> 0 '
      'ORDER BY units $order, rev $order $lim',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales, _db.saleLines, _db.variants, _db.products},
    ).get();
    return rows
        .map((r) => VariantSales(
              productName: r.read<String>('pname'),
              size: r.read<String?>('size'),
              color: r.read<String?>('color'),
              sku: r.read<String>('sku'),
              unitsSold: r.read<int>('units'),
              revenueCents: r.read<int>('rev'),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Margen por producto (último costo de la variante)
  // ---------------------------------------------------------------------------
  Future<List<ProductMargin>> marginByProduct(DateTime from, DateTime to) async {
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, '
      'COALESCE(SUM(sl.qty), 0) AS units, '
      'COALESCE(SUM(sl.line_total_cents), 0) AS rev, '
      'COALESCE(SUM(sl.qty * v.cost_cents), 0) AS cost '
      'FROM sale_lines sl '
      'JOIN sales s ON s.id = sl.sale_id '
      'JOIN variants v ON v.id = sl.variant_id '
      'JOIN products p ON p.id = v.product_id '
      'WHERE s.status IN $_soldStatuses AND s.created_at >= ? AND s.created_at < ? '
      'GROUP BY p.id HAVING units <> 0 '
      'ORDER BY (rev - cost) DESC',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales, _db.saleLines, _db.variants, _db.products},
    ).get();
    return rows
        .map((r) => ProductMargin(
              productName: r.read<String>('pname'),
              unitsSold: r.read<int>('units'),
              revenueCents: r.read<int>('rev'),
              costCents: r.read<int>('cost'),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Inventario muerto: con existencia y sin venta en los últimos [days] días
  // ---------------------------------------------------------------------------
  Future<List<DeadStockItem>> deadStock({int days = 60}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, v.sku AS sku, v.size AS size, v.color AS color, '
      'COALESCE(vs.on_hand, 0) AS on_hand, '
      '(SELECT MAX(s.created_at) FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id '
      "   WHERE sl.variant_id = v.id AND sl.qty > 0 AND s.status IN $_soldStatuses) AS last_sold "
      'FROM variants v '
      'JOIN products p ON p.id = v.product_id '
      'LEFT JOIN variant_stock vs ON vs.variant_id = v.id '
      'WHERE v.active = 1 AND COALESCE(vs.on_hand, 0) > 0 '
      'AND (last_sold IS NULL OR last_sold < ?) '
      'ORDER BY on_hand DESC, p.name ASC '
      'LIMIT 200',
      variables: [_d(cutoff)],
      readsFrom: {_db.variants, _db.products, _db.sales, _db.saleLines, _db.inventoryMovements},
    ).get();
    return rows.map((r) {
      final ls = r.read<DateTime?>('last_sold');
      return DeadStockItem(
        productName: r.read<String>('pname'),
        sku: r.read<String>('sku'),
        size: r.read<String?>('size'),
        color: r.read<String?>('color'),
        onHand: r.read<int>('on_hand'),
        lastSold: ls,
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Diferencias de caja por cajero (cortes cerrados)
  // ---------------------------------------------------------------------------
  Future<List<CashierVariance>> cashierVariances(DateTime from, DateTime to) async {
    final rows = await _db.customSelect(
      'SELECT pr.name AS name, COUNT(*) AS sessions, '
      'COALESCE(SUM(cs.variance_cents), 0) AS variance '
      'FROM cash_sessions cs '
      'JOIN profiles pr ON pr.id = COALESCE(cs.closed_by, cs.opened_by) '
      "WHERE cs.status = 'closed' AND cs.closed_at >= ? AND cs.closed_at < ? "
      'GROUP BY pr.id ORDER BY variance ASC',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.cashSessions, _db.profiles},
    ).get();
    return rows
        .map((r) => CashierVariance(
              name: r.read<String>('name'),
              sessions: r.read<int>('sessions'),
              totalVarianceCents: r.read<int>('variance'),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Tasa de devolución por producto
  // ---------------------------------------------------------------------------
  Future<List<ReturnRate>> returnRates(DateTime from, DateTime to) async {
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, '
      'COALESCE(SUM(CASE WHEN sl.qty > 0 THEN sl.qty ELSE 0 END), 0) AS sold, '
      'COALESCE(-SUM(CASE WHEN sl.qty < 0 THEN sl.qty ELSE 0 END), 0) AS returned '
      'FROM sale_lines sl '
      'JOIN sales s ON s.id = sl.sale_id '
      'JOIN variants v ON v.id = sl.variant_id '
      'JOIN products p ON p.id = v.product_id '
      'WHERE s.status IN $_soldStatuses AND s.created_at >= ? AND s.created_at < ? '
      'GROUP BY p.id HAVING returned > 0 '
      'ORDER BY (CAST(returned AS REAL) / NULLIF(sold, 0)) DESC',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales, _db.saleLines, _db.variants, _db.products},
    ).get();
    return rows
        .map((r) => ReturnRate(
              productName: r.read<String>('pname'),
              sold: r.read<int>('sold'),
              returned: r.read<int>('returned'),
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Ventas por vendedor (o cajero si no hubo vendedor asignado)
  // ---------------------------------------------------------------------------
  Future<List<SalespersonSales>> salesBySalesperson(
      DateTime from, DateTime to) async {
    final rows = await _db.customSelect(
      'SELECT pr.name AS name, COUNT(*) AS n, '
      'COALESCE(SUM(s.total_cents), 0) AS rev '
      'FROM sales s '
      'JOIN profiles pr ON pr.id = COALESCE(s.salesperson_id, s.cashier_id) '
      "WHERE s.status = 'completed' AND s.created_at >= ? AND s.created_at < ? "
      'GROUP BY pr.id ORDER BY rev DESC',
      variables: [_d(from), _d(to)],
      readsFrom: {_db.sales, _db.profiles},
    ).get();
    return rows
        .map((r) => SalespersonSales(
              name: r.read<String>('name'),
              salesCount: r.read<int>('n'),
              revenueCents: r.read<int>('rev'),
            ))
        .toList();
  }
}
