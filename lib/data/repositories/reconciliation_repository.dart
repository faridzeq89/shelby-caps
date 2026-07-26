import '../local/database.dart';

/// Una inconsistencia detectada (solo lectura; no corrige nada).
class ReconIssue {
  const ReconIssue(this.title, this.detail);
  final String title;
  final String detail;
}

class ReconGroup {
  const ReconGroup(this.name, this.explanation, this.issues);
  final String name;
  final String explanation;
  final List<ReconIssue> issues;
}

/// Reporte de reconciliación (Fase 8): detecta estados que la operación
/// local-first puede dejar (stock negativo por "la pieza en la mano gana",
/// folios duplicados entre tablets, pagos que no cuadran). No modifica datos.
class ReconciliationRepository {
  ReconciliationRepository(this._db);
  final AppDatabase _db;

  Future<List<ReconGroup>> run() async {
    return [
      ReconGroup(
        'Stock negativo',
        'Se vendió más de lo que el sistema tenía (la pieza en la mano gana). '
            'Revisa y ajusta con un conteo o recepción.',
        await _negativeStock(),
      ),
      ReconGroup(
        'Sobre-reservado',
        'Hay más apartado que existencia física (disponible negativo).',
        await _overReserved(),
      ),
      ReconGroup(
        'Pagos que no cuadran',
        'Ventas completadas donde la suma de pagos no coincide con el total.',
        await _paymentMismatches(),
      ),
    ];
  }

  Future<int> issueCount() async {
    final groups = await run();
    return groups.fold<int>(0, (s, g) => s + g.issues.length);
  }

  Future<List<ReconIssue>> _negativeStock() async {
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, v.sku AS sku, vs.on_hand AS oh '
      'FROM variant_stock vs '
      'JOIN variants v ON v.id = vs.variant_id '
      'JOIN products p ON p.id = v.product_id '
      'WHERE vs.on_hand < 0 ORDER BY vs.on_hand ASC',
      readsFrom: {_db.variants, _db.products, _db.inventoryMovements},
    ).get();
    return rows
        .map((r) => ReconIssue(
            '${r.read<String>('pname')} (${r.read<String>('sku')})',
            'Existencia: ${r.read<int>('oh')}'))
        .toList();
  }

  Future<List<ReconIssue>> _overReserved() async {
    final rows = await _db.customSelect(
      'SELECT p.name AS pname, v.sku AS sku, vs.on_hand AS oh, vs.reserved AS rv '
      'FROM variant_stock vs '
      'JOIN variants v ON v.id = vs.variant_id '
      'JOIN products p ON p.id = v.product_id '
      'WHERE (vs.on_hand - vs.reserved) < 0 ORDER BY (vs.on_hand - vs.reserved) ASC',
      readsFrom: {_db.variants, _db.products, _db.inventoryMovements},
    ).get();
    return rows
        .map((r) => ReconIssue(
            '${r.read<String>('pname')} (${r.read<String>('sku')})',
            'En tienda ${r.read<int>('oh')}, apartado ${r.read<int>('rv')} '
                '→ disponible ${r.read<int>('oh') - r.read<int>('rv')}'))
        .toList();
  }

  Future<List<ReconIssue>> _paymentMismatches() async {
    final rows = await _db.customSelect(
      'SELECT s.folio AS folio, s.total_cents AS tc, '
      'COALESCE(SUM(pm.amount_cents), 0) AS paid '
      'FROM sales s LEFT JOIN payments pm ON pm.sale_id = s.id '
      "WHERE s.status = 'completed' "
      'GROUP BY s.id HAVING paid <> tc',
      readsFrom: {_db.sales, _db.payments},
    ).get();
    return rows.map((r) {
      final tc = r.read<int>('tc');
      final paid = r.read<int>('paid');
      return ReconIssue('Folio ${r.read<String>('folio')}',
          'Total \$${(tc / 100).toStringAsFixed(2)} vs pagado \$${(paid / 100).toStringAsFixed(2)}');
    }).toList();
  }
}
