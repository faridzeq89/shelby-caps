import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/reports_repository.dart';
import '../../services/auth_controller.dart';
import '../customers/customers_screen.dart';
import '../sales/quotes_screen.dart';

/// Pantalla de inicio (panel del día), estilo Treinta: tarjeta-resumen con
/// ventas/balance/gastos de hoy + CTA para registrar venta, accesos rápidos y
/// mini-estadísticas del mes. Header carbón con hamburguesa.
class InicioScreen extends StatefulWidget {
  const InicioScreen({
    super.key,
    required this.onMenu,
    required this.onRegistrarVenta,
    required this.onGoBalance,
  });

  final VoidCallback onMenu;
  final VoidCallback onRegistrarVenta;
  final VoidCallback onGoBalance;

  @override
  State<InicioScreen> createState() => InicioScreenState();
}

class _Data {
  const _Data({
    required this.ventasHoy,
    required this.gastosHoy,
    required this.gananciaMes,
    required this.estrella,
  });
  final int ventasHoy;
  final int gastosHoy;
  final int gananciaMes;
  final String? estrella;
  int get balanceHoy => ventasHoy - gastosHoy;
}

class InicioScreenState extends State<InicioScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final ReportsRepository _reports = ReportsRepository(_db);
  late final ExpenseRepository _expenses = ExpenseRepository(_db);
  late Future<_Data> _future = _load();

  void reload() => setState(() => _future = _load());

  Future<_Data> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final hoy = await _reports.periodSummary(today, tomorrow);
    final gastosHoy = await _expenses.totalBetween(today, tomorrow);
    final mes = await _reports.periodSummary(monthStart, tomorrow);
    final gastosMes = await _expenses.totalBetween(monthStart, tomorrow);
    final top = await _reports.variantSales(monthStart, tomorrow, limit: 1);

    return _Data(
      ventasHoy: hoy.netCents,
      gastosHoy: gastosHoy,
      gananciaMes: mes.netCents - gastosMes,
      estrella: top.isEmpty ? null : top.first.productName,
    );
  }

  String _m(int c) => '\$${(c / 100).toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: widget.onMenu,
          tooltip: 'Menú',
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('SHELBY CAPS',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5)),
            Text(auth.isAdmin ? 'Propietario' : 'Cajero',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFB6AD97),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => reload(),
        child: FutureBuilder<_Data>(
          future: _future,
          builder: (context, snap) {
            final d = snap.data;
            return ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _heroCard(context, d),
                const SizedBox(height: 18),
                Text('Accesos rápidos',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _tiles(context),
                const SizedBox(height: 18),
                _miniStats(context, d),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, _Data? d) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ventas hoy',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(d == null ? '—' : _m(d.ventasHoy),
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _kv('Balance', d == null ? '—' : _m(d.balanceHoy),
                      (d?.balanceHoy ?? 0) >= 0
                          ? const Color(0xFF2F6E46)
                          : theme.colorScheme.error),
                ),
                Expanded(
                  child: _kv('Gastos hoy', d == null ? '—' : _m(d.gastosHoy),
                      theme.colorScheme.error,
                      alignEnd: true),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.onRegistrarVenta,
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Registrar venta'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, Color color, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(k,
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600)),
        Text(v,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _tiles(BuildContext context) {
    final tiles = [
      _Tile(Icons.point_of_sale, 'Vender', widget.onRegistrarVenta),
      _Tile(Icons.request_quote_outlined, 'Cotizar',
          () => _push(const QuotesScreen())),
      _Tile(Icons.people_alt_outlined, 'Clientes',
          () => _push(const CustomersScreen())),
      _Tile(Icons.bar_chart_outlined, 'Balance', widget.onGoBalance),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.85,
      children: [for (final t in tiles) _tileWidget(context, t)],
    );
  }

  Widget _tileWidget(BuildContext context, _Tile t) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: t.onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(15),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(t.icon, color: const Color(0xFF846826), size: 24),
            const SizedBox(height: 6),
            Text(t.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _miniStats(BuildContext context, _Data? d) {
    return Row(
      children: [
        Expanded(
          child: _statCard(context, 'Estrella del mes',
              d?.estrella ?? '—', small: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
              context, 'Ganancia del mes', d == null ? '—' : _m(d.gananciaMes)),
        ),
      ],
    );
  }

  Widget _statCard(BuildContext context, String h, String b,
      {bool small = false}) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(15),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(b,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: small ? 15 : 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    reload();
  }
}

class _Tile {
  const _Tile(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
