import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/cash_session_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';


class CashSessionScreen extends StatefulWidget {
  const CashSessionScreen({super.key});

  @override
  State<CashSessionScreen> createState() => _CashSessionScreenState();
}

class _CashData {
  _CashData(this.session, this.summary, this.sales);
  final CashSession? session;
  final CashSessionSummary? summary;
  final List<Sale> sales;
}

class _CashSessionScreenState extends State<CashSessionScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CashSessionRepository _cash = CashSessionRepository(_db);
  late final SalesRepository _sales = SalesRepository(_db);
  int? _locationId;
  late Future<_CashData> _future = _load();

  Profile get _user => context.read<AuthController>().currentUser!;

  Future<_CashData> _load() async {
    _locationId ??= (await _db.select(_db.locations).getSingleOrNull())?.id;
    if (_locationId == null) return _CashData(null, null, const []);
    final session = await _cash.currentOpen(_locationId!);
    if (session == null) return _CashData(null, null, const []);
    return _CashData(
      session,
      await _cash.summary(session),
      await _cash.salesOfSession(session),
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<int?> _askPesos(String title, {String initial = '0'}) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '\$'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok != true) return null;
    final v = double.tryParse(ctrl.text.trim());
    return v == null ? null : (v * 100).round();
  }

  Future<void> _open() async {
    final float = await _askPesos('Fondo de apertura');
    if (float == null || _locationId == null) return;
    try {
      await _cash.open(
          actor: _user, locationId: _locationId!, openingFloatCents: float);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _movement(CashSession s, CashMovementKind kind) async {
    final amount =
        await _askPesos(kind == CashMovementKind.withdrawal ? 'Retiro' : 'Depósito');
    if (amount == null || amount <= 0) return;
    await _cash.recordCash(
        actor: _user, session: s, kind: kind, amountCents: amount);
    _reload();
  }

  Future<void> _close(CashSession s, CashSessionSummary sum) async {
    final counted = await _askPesos(
        'Cierre: efectivo contado\n(esperado ${money(sum.expectedCashCents)})');
    if (counted == null) return;
    final closed = await _cash.close(actor: _user, session: s, countedCents: counted);
    if (!mounted) return;
    final variance = closed.varianceCents ?? 0;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Caja cerrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Esperado: ${money(closed.expectedCents ?? 0)}'),
            Text('Contado: ${money(closed.closingCountCents ?? 0)}'),
            Text(
              variance == 0
                  ? 'Sin diferencia'
                  : variance > 0
                      ? 'Sobrante: ${money(variance)}'
                      : 'Faltante: ${money(-variance)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: variance == 0 ? AppColors.success : AppColors.danger,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo')),
        ],
      ),
    );
    _reload();
  }

  Future<Profile?> _authorizedActor() async {
    if (Permissions.canCancelSale(_user.role)) return _user;
    final auth = context.read<AuthController>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Autorización de gerente'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN de gerente'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Autorizar')),
        ],
      ),
    );
    if (ok != true) return null;
    return auth.verifyPrivilegedPin(ctrl.text);
  }

  Future<void> _cancelSale(Sale sale) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancelar venta ${sale.folio}?'),
        content: const Text('Se regresa el stock y queda registrada la cancelación.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirm != true) return;
    final actor = await _authorizedActor();
    if (actor == null) {
      _toast('No autorizado');
      return;
    }
    try {
      await _sales.cancelSale(actor: actor, saleId: sale.id, reason: 'Cancelada en corte');
      _toast('Venta cancelada');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Corte de caja')),
      body: FutureBuilder<_CashData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          if (data.session == null) {
            return EmptyState(
              icon: Icons.lock_outline,
              title: 'No hay caja abierta',
              hint: 'Abre la caja con el fondo inicial para empezar a '
                  'registrar ventas del turno.',
              action: FilledButton.icon(
                onPressed: _open,
                icon: const Icon(Icons.lock_open),
                label: const Text('Abrir caja'),
              ),
            );
          }
          return _openView(data.session!, data.summary!, data.sales);
        },
      ),
    );
  }

  Widget _openView(
      CashSession s, CashSessionSummary sum, List<Sale> sales) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // El efectivo esperado es contra lo que el cajero cuenta el cajón:
        // va arriba y en grande, y el desglose queda como respaldo.
        SurfaceCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StatBlock(
                label: 'Efectivo esperado en caja',
                value: money(sum.expectedCashCents),
                size: 30,
              ),
              const Divider(height: 24),
              _row('Fondo de apertura', sum.openingFloatCents),
              _row('Ventas en efectivo', sum.cashSalesCents),
              _row('Ventas con tarjeta', sum.cardSalesCents),
              if (sum.otherSalesCents > 0)
                _row('Otras ventas', sum.otherSalesCents),
              _row('Depósitos', sum.depositsCents),
              _row('Retiros', -sum.withdrawalsCents),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _movement(s, CashMovementKind.withdrawal),
                icon: const Icon(Icons.remove),
                label: const Text('Retiro'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _movement(s, CashMovementKind.deposit),
                icon: const Icon(Icons.add),
                label: const Text('Depósito'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _close(s, sum),
          icon: const Icon(Icons.lock),
          label: const Text('Cerrar caja'),
        ),
        const SizedBox(height: 20),
        SectionHeader('Ventas del turno (${sales.length})'),
        if (sales.isEmpty)
          const SurfaceCard(
            child: Text('Todavía no hay ventas en este turno.'),
          )
        else
          for (final sale in sales) _saleRow(sale),
      ],
    );
  }

  Widget _row(String label, int cents, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
            Text(money(cents),
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
          ],
        ),
      );

  /// Renglón de venta del turno, con su folio y estado. Cancelar es una acción
  /// destructiva, así que va en el color de error y no como texto neutro.
  Widget _saleRow(Sale sale) {
    final theme = Theme.of(context);
    final cancelled = sale.status == SaleStatus.cancelled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sale.folio,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  cancelled
                      ? StatusPill('Cancelada', color: theme.colorScheme.error)
                      : const StatusPill('Completada',
                          color: AppColors.success),
                ],
              ),
            ),
            Text(money(sale.totalCents),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                    color: cancelled ? theme.hintColor : null)),
            if (!cancelled)
              TextButton(
                onPressed: () => _cancelSale(sale),
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
                child: const Text('Cancelar'),
              ),
          ],
        ),
      ),
    );
  }
}
