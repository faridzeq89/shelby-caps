import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/reports_repository.dart';
import 'report_export.dart';

/// Un periodo con nombre para el selector.
class _Period {
  const _Period(this.label, this.from, this.to, this.slug);
  final String label;
  final DateTime from;
  final DateTime to;
  final String slug;
}

/// Tabla lista para mostrar y exportar (mismas columnas para pantalla y CSV).
class ReportTable {
  ReportTable(this.headers, this.rows);
  final List<String> headers;
  final List<List<String>> rows;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ReportsRepository _repo =
      ReportsRepository(context.read<AppDatabase>());

  int _periodIndex = 2; // 30 días por defecto
  late Future<_HubData> _future = _load();

  List<_Period> _periods() {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    return [
      _Period('Hoy', startToday, startToday.add(const Duration(days: 1)), 'hoy'),
      _Period('7 días', now.subtract(const Duration(days: 7)), now, '7d'),
      _Period('30 días', now.subtract(const Duration(days: 30)), now, '30d'),
      _Period('60 días', now.subtract(const Duration(days: 60)), now, '60d'),
    ];
  }

  _Period get _period => _periods()[_periodIndex];

  Future<_HubData> _load() async {
    final p = _period;
    final length = p.to.difference(p.from);
    final prevFrom = p.from.subtract(length);
    final summary = await _repo.periodSummary(p.from, p.to);
    final prev = await _repo.periodSummary(prevFrom, p.from);
    return _HubData(summary, prev);
  }

  void _reload() => setState(() => _future = _load());

  String _money(int c) => '\$${ReportExport.money(c)}';

  Future<void> _open(String title, String filenameBase,
      Future<ReportTable> Function() builder) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ReportDetailScreen(
        title: title,
        filename: 'reporte_${filenameBase}_${_period.slug}.csv',
        builder: builder,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reportes')),
      body: FutureBuilder<_HubData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          final s = data.current;
          final delta = data.current.netCents - data.previous.netCents;
          final pct = data.previous.netCents == 0
              ? null
              : delta / data.previous.netCents * 100;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Selector de periodo.
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < _periods().length; i++)
                    ButtonSegment(value: i, label: Text(_periods()[i].label)),
                ],
                selected: {_periodIndex},
                onSelectionChanged: (sel) {
                  setState(() => _periodIndex = sel.first);
                  _reload();
                },
              ),
              const SizedBox(height: 16),
              // Resumen.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ventas netas', style: theme.textTheme.labelLarge),
                      Text(_money(s.netCents),
                          style: theme.textTheme.headlineMedium),
                      if (pct != null)
                        Text(
                          '${pct >= 0 ? '▲' : '▼'} ${pct.abs().toStringAsFixed(1)}% vs periodo anterior',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: pct >= 0
                                ? Colors.green.shade700
                                : theme.colorScheme.error,
                          ),
                        ),
                      const Divider(height: 24),
                      _kv('Ventas', '${s.salesCount}'),
                      _kv('Piezas vendidas', '${s.itemsSold}'),
                      _kv('IVA incluido', _money(s.taxCents)),
                      _kv('Descuentos', _money(s.discountCents)),
                      _kv('Devoluciones',
                          '${s.returnsCount} · ${_money(s.returnsCents)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _tile(Icons.lightbulb_outline, 'Recomendaciones',
                  'Qué reabastecer, ofertar o descontar', () {
                _open('Recomendaciones', 'recomendaciones', () async {
                  final recs = await _repo.recommendations();
                  return ReportTable(
                    ['Acción', 'Producto', 'SKU', 'Motivo'],
                    [
                      for (final r in recs)
                        [r.action, r.productName, r.sku, r.reason],
                    ],
                  );
                });
              }),
              _tile(Icons.trending_up, 'Más vendidos',
                  'Top por piezas en el periodo', () {
                _open('Más vendidos', 'top_vendidos', () async {
                  final rows = await _repo.variantSales(_period.from, _period.to,
                      limit: 50);
                  return ReportTable(
                    ['Producto', 'Talla', 'Color', 'SKU', 'Piezas', 'Ingreso'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          r.size ?? '',
                          r.color ?? '',
                          r.sku,
                          '${r.unitsSold}',
                          ReportExport.money(r.revenueCents),
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.trending_down, 'Menos vendidos',
                  'Los que se venden poco en el periodo', () {
                _open('Menos vendidos', 'menos_vendidos', () async {
                  final rows = await _repo.variantSales(_period.from, _period.to,
                      limit: 50, ascending: true);
                  return ReportTable(
                    ['Producto', 'Talla', 'Color', 'SKU', 'Piezas', 'Ingreso'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          r.size ?? '',
                          r.color ?? '',
                          r.sku,
                          '${r.unitsSold}',
                          ReportExport.money(r.revenueCents),
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.color_lens_outlined, 'Tallas y colores',
                  'Qué combinaciones se venden', () {
                _open('Tallas y colores', 'talla_color', () async {
                  final rows =
                      await _repo.variantSales(_period.from, _period.to);
                  return ReportTable(
                    ['Producto', 'Talla', 'Color', 'Piezas', 'Ingreso'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          r.size ?? '',
                          r.color ?? '',
                          '${r.unitsSold}',
                          ReportExport.money(r.revenueCents),
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.percent, 'Margen por producto',
                  'Ingreso menos costo (último costo)', () {
                _open('Margen por producto', 'margen', () async {
                  final rows =
                      await _repo.marginByProduct(_period.from, _period.to);
                  return ReportTable(
                    ['Producto', 'Piezas', 'Ingreso', 'Costo', 'Margen', '%'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          '${r.unitsSold}',
                          ReportExport.money(r.revenueCents),
                          ReportExport.money(r.costCents),
                          ReportExport.money(r.marginCents),
                          '${r.marginPct.toStringAsFixed(1)}%',
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.inventory_2_outlined, 'Inventario muerto',
                  'Con existencia y sin venta en 60 días', () {
                _open('Inventario muerto', 'inventario_muerto', () async {
                  final rows = await _repo.deadStock(days: 60);
                  final fmt = DateFormat('yyyy-MM-dd');
                  return ReportTable(
                    ['Producto', 'Talla', 'Color', 'SKU', 'Existencia', 'Última venta'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          r.size ?? '',
                          r.color ?? '',
                          r.sku,
                          '${r.onHand}',
                          r.lastSold == null ? 'nunca' : fmt.format(r.lastSold!),
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.assignment_return_outlined, 'Devoluciones por producto',
                  'Tasa de devolución en el periodo', () {
                _open('Devoluciones por producto', 'devoluciones', () async {
                  final rows =
                      await _repo.returnRates(_period.from, _period.to);
                  return ReportTable(
                    ['Producto', 'Vendidas', 'Devueltas', 'Tasa'],
                    [
                      for (final r in rows)
                        [
                          r.productName,
                          '${r.sold}',
                          '${r.returned}',
                          '${r.rate.toStringAsFixed(1)}%',
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.badge_outlined, 'Ventas por vendedor',
                  'Atribución por vendedor/cajero', () {
                _open('Ventas por vendedor', 'vendedores', () async {
                  final rows =
                      await _repo.salesBySalesperson(_period.from, _period.to);
                  return ReportTable(
                    ['Vendedor', 'Ventas', 'Ingreso'],
                    [
                      for (final r in rows)
                        [
                          r.name,
                          '${r.salesCount}',
                          ReportExport.money(r.revenueCents),
                        ],
                    ],
                  );
                });
              }),
              _tile(Icons.account_balance_wallet_outlined,
                  'Diferencias de caja', 'Arqueos por cajero', () {
                _open('Diferencias de caja', 'cajeros', () async {
                  final rows =
                      await _repo.cashierVariances(_period.from, _period.to);
                  return ReportTable(
                    ['Cajero', 'Cortes', 'Diferencia'],
                    [
                      for (final r in rows)
                        [
                          r.name,
                          '${r.sessions}',
                          ReportExport.money(r.totalVarianceCents),
                        ],
                    ],
                  );
                });
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(k), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))],
        ),
      );

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _HubData {
  _HubData(this.current, this.previous);
  final PeriodSummary current;
  final PeriodSummary previous;
}

/// Muestra una tabla de reporte y permite exportarla a CSV.
class _ReportDetailScreen extends StatefulWidget {
  const _ReportDetailScreen({
    required this.title,
    required this.filename,
    required this.builder,
  });
  final String title;
  final String filename;
  final Future<ReportTable> Function() builder;

  @override
  State<_ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<_ReportDetailScreen> {
  late final Future<ReportTable> _future = widget.builder();
  bool _exporting = false;

  Future<void> _export(ReportTable table) async {
    setState(() => _exporting = true);
    try {
      final csv = ReportExport.toCsv(table.headers, table.rows);
      await ReportExport.share(csv, widget.filename);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<ReportTable>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final table = snap.data!;
          if (table.rows.isEmpty) {
            return const Center(child: Text('Sin datos en este periodo.'));
          }
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        for (final h in table.headers)
                          DataColumn(label: Text(h)),
                      ],
                      rows: [
                        for (final r in table.rows)
                          DataRow(cells: [for (final c in r) DataCell(Text(c))]),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _exporting ? null : () => _export(table),
                      icon: _exporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.ios_share),
                      label: const Text('Exportar CSV (Excel)'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
