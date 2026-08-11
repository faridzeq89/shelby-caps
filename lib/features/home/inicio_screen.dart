import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
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

  String _m(int c) => money(c, decimals: false);

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
        title: AppBarTitle(
          title: 'SHELBY CAPS',
          subtitle: auth.isAdmin ? 'Propietario' : 'Cajero',
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
                const SectionHeader('Accesos rápidos'),
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
                  child: StatBlock(
                    label: 'Balance',
                    value: d == null ? '—' : _m(d.balanceHoy),
                    size: 18,
                    color: (d?.balanceHoy ?? 0) >= 0
                        ? AppColors.success
                        : theme.colorScheme.error,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: 'Gastos hoy',
                    value: d == null ? '—' : _m(d.gastosHoy),
                    size: 18,
                    color: theme.colorScheme.error,
                    alignEnd: true,
                  ),
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

  Widget _tiles(BuildContext context) {
    return QuickTileRow(
      tiles: [
        QuickTile(
          icon: Icons.point_of_sale,
          label: 'Vender',
          onTap: widget.onRegistrarVenta,
        ),
        QuickTile(
          icon: Icons.request_quote_outlined,
          label: 'Cotizar',
          onTap: () => _push(const QuotesScreen()),
        ),
        QuickTile(
          icon: Icons.people_alt_outlined,
          label: 'Clientes',
          onTap: () => _push(const CustomersScreen()),
        ),
        QuickTile(
          icon: Icons.bar_chart_outlined,
          label: 'Balance',
          onTap: widget.onGoBalance,
        ),
      ],
    );
  }

  Widget _miniStats(BuildContext context, _Data? d) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Estrella del mes',
            value: d?.estrella ?? '—',
            size: 15,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Ganancia del mes',
            value: d == null ? '—' : _m(d.gananciaMes),
          ),
        ),
      ],
    );
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    reload();
  }
}
