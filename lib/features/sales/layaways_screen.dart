import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/layaway_repository.dart';
import '../../data/repositories/sales_repository.dart' show CheckoutLine;
import '../../services/auth_controller.dart';
import 'layaway_receipt.dart';
import 'ticket_service.dart';
import 'variant_picker.dart';

final _df = DateFormat('dd/MM/yyyy');

class LayawaysScreen extends StatefulWidget {
  const LayawaysScreen({super.key});

  @override
  State<LayawaysScreen> createState() => _LayawaysScreenState();
}

class _LayawaysScreenState extends State<LayawaysScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final LayawayRepository _repo = LayawayRepository(_db);
  int? _locationId;
  late Future<List<LayawaySummary>> _future = _load();

  Profile get _user => context.read<AuthController>().currentUser!;

  Future<List<LayawaySummary>> _load() async {
    _locationId ??= (await _db.select(_db.locations).getSingleOrNull())?.id;
    if (_locationId == null) return [];
    return _repo.activeLayaways(_locationId!);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _processExpired() async {
    final n = await _repo.expireOverdue(actor: _user);
    _toast(n == 0 ? 'Sin apartados vencidos' : '$n apartado(s) vencido(s) procesado(s)');
    _reload();
  }

  Future<void> _new() async {
    if (_locationId == null) return;
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _NewLayawayScreen(locationId: _locationId!),
    ));
    if (done == true) _reload();
  }

  Future<void> _open(String saleId) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LayawayDetailScreen(saleId: saleId),
    ));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apartados'),
        actions: [
          IconButton(
            onPressed: _processExpired,
            icon: const Icon(Icons.event_busy),
            tooltip: 'Procesar vencidos',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo apartado'),
      ),
      body: FutureBuilder<List<LayawaySummary>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border,
              title: 'Sin apartados activos',
              hint: 'Los apartados que registres aparecerán aquí con su saldo '
                  'y su fecha de vencimiento.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = list[i];
              final overdue = s.terms.expiresAt.isBefore(DateTime.now());
              final soon = !overdue &&
                  s.terms.expiresAt
                      .isBefore(DateTime.now().add(const Duration(days: 5)));
              return SurfaceCard(
                onTap: () => _open(s.sale.id),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.customerName ?? 'Cliente',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              StatusPill(s.sale.folio),
                              const SizedBox(width: 6),
                              if (overdue)
                                StatusPill('Vencido',
                                    icon: Icons.event_busy,
                                    color: theme.colorScheme.error)
                              else if (soon)
                                const StatusPill('Por vencer',
                                    icon: Icons.schedule),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Vence ${_df.format(s.terms.expiresAt)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    StatBlock(
                      label: 'Saldo',
                      value: money(s.balanceCents),
                      size: 18,
                      alignEnd: true,
                      color: overdue ? theme.colorScheme.error : null,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Nuevo apartado
// ===========================================================================

class _Item {
  _Item(this.product, this.variant, this.unitPriceCents, this.qty);
  final Product product;
  final Variant variant;
  final int unitPriceCents;
  int qty;
  int get lineTotal => unitPriceCents * qty;
  String get title =>
      '${product.name} ${variant.size ?? ''} ${variant.color ?? ''}'.trim();
}

class _NewLayawayScreen extends StatefulWidget {
  const _NewLayawayScreen({required this.locationId});
  final int locationId;

  @override
  State<_NewLayawayScreen> createState() => _NewLayawayScreenState();
}

class _NewLayawayScreenState extends State<_NewLayawayScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final LayawayRepository _repo = LayawayRepository(_db);
  late final CatalogRepository _catalog = CatalogRepository(_db);
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _deposit = TextEditingController();
  final _items = <_Item>[];
  bool _depositTouched = false;

  Profile get _user => context.read<AuthController>().currentUser!;
  int get _total => _items.fold(0, (s, i) => s + i.lineTotal);
  int get _required => (_total * LayawayRepository.depositPercent / 100).round();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _deposit.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addItem() async {
    final picked = await pickProductAndVariant(context, _catalog);
    if (picked == null) return;
    setState(() {
      final existing =
          _items.where((i) => i.variant.id == picked.$2.id).firstOrNull;
      if (existing != null) {
        existing.qty++;
      } else {
        _items.add(_Item(picked.$1, picked.$2,
            effectivePrice(picked.$1, picked.$2), 1));
      }
      if (!_depositTouched) {
        _deposit.text = (_required / 100).toStringAsFixed(2);
      }
    });
  }

  Future<void> _create() async {
    if (_items.isEmpty) {
      _toast('Agrega al menos una pieza');
      return;
    }
    if (_name.text.trim().isEmpty) {
      _toast('El nombre del cliente es obligatorio');
      return;
    }
    final depositCents =
        ((double.tryParse(_deposit.text.trim()) ?? 0) * 100).round();
    if (depositCents < _required) {
      _toast('El anticipo mínimo es ${money(_required)} (30%)');
      return;
    }
    try {
      final customerId = await _repo.createCustomer(
          _name.text.trim(),
          _phone.text.trim().isEmpty ? null : _phone.text.trim());
      final result = await _repo.createLayaway(
        actor: _user,
        locationId: widget.locationId,
        customerId: customerId,
        lines: [
          for (final i in _items)
            CheckoutLine(
                product: i.product,
                variant: i.variant,
                qty: i.qty,
                unitPriceCents: i.unitPriceCents),
        ],
        depositCents: depositCents,
      );
      // Comprobante.
      final ticketCfg = await TicketConfig.load(_db);
      await Printing.layoutPdf(
        onLayout: (_) => LayawayReceiptService.build(
          config: ticketCfg,
          folio: result.folio,
          customerName: _name.text.trim(),
          dateTime: DateTime.now(),
          lines: [
            for (final i in _items)
              LayawayReceiptLine(i.title, i.qty, i.lineTotal),
          ],
          totalCents: result.totalCents,
          paidCents: depositCents,
          balanceCents: result.balanceCents,
          dueDate: DateTime.now()
              .add(const Duration(days: LayawayRepository.termDays)),
        ),
        name: 'apartado_${result.folio}',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo apartado')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre del cliente'),
          ),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Agregar pieza'),
          ),
          for (final i in _items)
            ListTile(
              title: Text(i.title),
              subtitle: Text(money(i.unitPriceCents)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      i.qty--;
                      if (i.qty <= 0) _items.remove(i);
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${i.qty}'),
                  IconButton(
                    onPressed: () => setState(() => i.qty++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          const Divider(),
          Text('Total: ${money(_total)}',
              style: Theme.of(context).textTheme.titleMedium),
          Text('Anticipo mínimo (30%): ${money(_required)}'),
          TextField(
            controller: _deposit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Anticipo', prefixText: '\$'),
            onChanged: (_) => _depositTouched = true,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.bookmark_add),
            label: const Text('Crear apartado'),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Detalle de apartado
// ===========================================================================

class _LayawayDetailScreen extends StatefulWidget {
  const _LayawayDetailScreen({required this.saleId});
  final String saleId;

  @override
  State<_LayawayDetailScreen> createState() => _LayawayDetailScreenState();
}

class _Detail {
  _Detail(this.sale, this.terms, this.customer, this.lines, this.payments,
      this.balance);
  final Sale sale;
  final LayawayTerm terms;
  final Customer? customer;
  final List<(SaleLine, String)> lines; // línea + descripción
  final List<Payment> payments;
  final int balance;
}

class _LayawayDetailScreenState extends State<_LayawayDetailScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final LayawayRepository _repo = LayawayRepository(_db);
  late Future<_Detail> _future = _load();

  Profile get _user => context.read<AuthController>().currentUser!;

  Future<_Detail> _load() async {
    final sale = await (_db.select(_db.sales)
          ..where((t) => t.id.equals(widget.saleId)))
        .getSingle();
    final terms = await (_db.select(_db.layawayTerms)
          ..where((t) => t.saleId.equals(widget.saleId)))
        .getSingle();
    Customer? customer;
    if (sale.customerId != null) {
      customer = await (_db.select(_db.customers)
            ..where((t) => t.id.equals(sale.customerId!)))
          .getSingleOrNull();
    }
    final rawLines = await _repo.linesOf(widget.saleId);
    final lines = <(SaleLine, String)>[];
    for (final l in rawLines) {
      final v = await (_db.select(_db.variants)
            ..where((t) => t.id.equals(l.variantId)))
          .getSingle();
      final p = await (_db.select(_db.products)
            ..where((t) => t.id.equals(v.productId)))
          .getSingle();
      lines.add((l, '${p.name} ${v.size ?? ''} ${v.color ?? ''}'.trim()));
    }
    return _Detail(sale, terms, customer, lines,
        await _repo.paymentsOf(widget.saleId), await _repo.balance(widget.saleId));
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _abonar(_Detail d) async {
    final ctrl = TextEditingController(
        text: (d.balance / 100).toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Abonar (saldo ${money(d.balance)})'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(prefixText: '\$'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Abonar')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = ((double.tryParse(ctrl.text.trim()) ?? 0) * 100).round();
    if (amount <= 0) return;
    await _repo.addPayment(
        actor: _user, saleId: widget.saleId, amountCents: amount);
    _reload();
  }

  Future<void> _liquidar(_Detail d) async {
    if (d.balance > 0) {
      _toast('Aún hay saldo pendiente');
      return;
    }
    try {
      await _repo.settle(actor: _user, saleId: widget.saleId);
      // Ticket final con los pagos acumulados.
      final ticketCfg = await TicketConfig.load(_db);
      await Printing.layoutPdf(
        onLayout: (_) => TicketService.buildPdf(
          config: ticketCfg,
          TicketData(
          folio: d.sale.folio,
          dateTime: DateTime.now(),
          cashierName: _user.name,
          lines: [
            for (final (l, desc) in d.lines)
              TicketLine(
                  description: desc,
                  qty: l.qty,
                  unitPriceCents: l.unitPriceCents,
                  lineTotalCents: l.lineTotalCents),
          ],
          subtotalCents: d.sale.totalCents,
          discountCents: 0,
          taxCents: d.sale.taxCents,
          totalCents: d.sale.totalCents,
          payments: [
            for (final p in d.payments)
              (p.reference == 'anticipo' ? 'Anticipo' : 'Abono', p.amountCents),
          ],
          changeCents: 0,
          gift: false,
        )),
        name: 'apartado_liquidado_${d.sale.folio}',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _reprint(_Detail d) async {
    final paid = d.sale.totalCents - d.balance;
    final ticketCfg = await TicketConfig.load(_db);
    await Printing.layoutPdf(
      onLayout: (_) => LayawayReceiptService.build(
        config: ticketCfg,
        folio: d.sale.folio,
        customerName: d.customer?.name ?? 'Cliente',
        dateTime: d.sale.createdAt,
        lines: [
          for (final (l, desc) in d.lines)
            LayawayReceiptLine(desc, l.qty, l.lineTotalCents),
        ],
        totalCents: d.sale.totalCents,
        paidCents: paid,
        balanceCents: d.balance,
        dueDate: d.terms.dueDate,
      ),
      name: 'apartado_${d.sale.folio}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apartado')),
      body: FutureBuilder<_Detail>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(d.customer?.name ?? 'Cliente',
                  style: Theme.of(context).textTheme.titleLarge),
              Text('${d.sale.folio} · vence ${_df.format(d.terms.dueDate)}'),
              const Divider(),
              const Text('Piezas', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final (l, desc) in d.lines)
                ListTile(
                  dense: true,
                  title: Text(desc),
                  trailing: Text('${l.qty} x ${money(l.unitPriceCents)}'),
                ),
              const Divider(),
              const Text('Pagos', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final p in d.payments)
                ListTile(
                  dense: true,
                  title: Text(p.reference == 'anticipo' ? 'Anticipo' : 'Abono'),
                  trailing: Text(money(p.amountCents)),
                ),
              const Divider(),
              _row('Total', d.sale.totalCents),
              _row('Pagado', d.sale.totalCents - d.balance),
              _row('SALDO', d.balance, bold: true),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _abonar(d),
                icon: const Icon(Icons.payments),
                label: const Text('Abonar'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: d.balance == 0 ? () => _liquidar(d) : null,
                icon: const Icon(Icons.check_circle),
                label: const Text('Liquidar y entregar'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _reprint(d),
                icon: const Icon(Icons.print),
                label: const Text('Imprimir comprobante'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, int cents, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
            Text(money(cents),
                style: TextStyle(
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
}
