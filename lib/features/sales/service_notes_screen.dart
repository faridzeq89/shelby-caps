import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/app_dropdown.dart';
import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/sales_repository.dart';
import '../../data/repositories/service_note_repository.dart';
import '../../services/auth_controller.dart';
import 'pdf_actions.dart';
import 'service_note_ticket.dart';
import 'ticket_service.dart';

String _paymentLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Efectivo',
      PaymentMethod.card => 'Tarjeta',
      PaymentMethod.transfer => 'Transferencia',
      PaymentMethod.creditNote => 'Nota de crédito',
      PaymentMethod.giftCard => 'Tarjeta de regalo',
    };

/// Notas de servicio (limpieza de tenis/gorra/bolsa): crear, ver pendientes y
/// cobrar. La nota solo describe el trabajo — sin precio ni inventario — y el
/// cobro es una venta directa (sin productos) que la liga y la marca pagada.
class ServiceNotesScreen extends StatefulWidget {
  const ServiceNotesScreen({super.key});

  @override
  State<ServiceNotesScreen> createState() => _ServiceNotesScreenState();
}

class _ServiceNotesScreenState extends State<ServiceNotesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final ServiceNoteRepository _repo = ServiceNoteRepository(_db);
  late final SalesRepository _sales = SalesRepository(_db);
  late Future<List<ServiceNote>> _future = _repo.all();

  Profile get _actor => context.read<AuthController>().currentUser!;

  void _reload() => setState(() => _future = _repo.all());

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<int?> _locationId() async {
    final loc = await _db.select(_db.locations).getSingleOrNull();
    return loc?.id;
  }

  Future<void> _printNote(ServiceNote note) async {
    final cfg = await TicketConfig.load(_db);
    if (!mounted) return;
    await showDocumentActions(
      context,
      title: 'Nota ${note.folio}',
      filename: 'nota_${note.folio}',
      shareHint: 'Dársela o mandársela al cliente para reclamar su pieza',
      build: (_) => ServiceNoteTicket.build(note, config: cfg),
    );
  }

  Future<void> _new() async {
    final note = await showModalBottomSheet<ServiceNote>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceNoteForm(repo: _repo),
    );
    if (note == null) return;
    _reload();
    if (mounted) await _printNote(note);
  }

  Future<void> _cobrar(ServiceNote note) async {
    final locId = await _locationId();
    if (!mounted) return;
    if (locId == null) {
      _toast('Falta configurar la sucursal');
      return;
    }
    final defaultDesc =
        'Servicio ${note.folio}: ${serviceItemTypeLabel(note.itemType)} — '
        '${note.customerName}';
    final input = await showModalBottomSheet<_DirectSaleInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DirectSaleForm(defaultDescription: defaultDesc),
    );
    if (input == null) return;
    try {
      final result = await _sales.sellDirect(
        cashier: _actor,
        locationId: locId,
        amountCents: input.amountCents,
        payments: [PaymentInput(input.method, input.amountCents)],
        description: input.description,
      );
      await _repo.markPaid(note.id, result.saleId);
      if (!mounted) return;
      _reload();
      final cfg = await TicketConfig.load(_db);
      if (!mounted) return;
      await showDocumentActions(
        context,
        title: 'Venta ${result.folio}',
        filename: 'venta_${result.folio}',
        build: (_) => TicketService.buildPdf(
          TicketData(
            folio: result.folio,
            dateTime: DateTime.now(),
            cashierName: _actor.name,
            lines: [
              TicketLine(
                description: input.description,
                qty: 1,
                unitPriceCents: input.amountCents,
                lineTotalCents: input.amountCents,
              ),
            ],
            subtotalCents: input.amountCents,
            discountCents: 0,
            taxCents: 0,
            totalCents: input.amountCents,
            payments: [(_paymentLabel(input.method), input.amountCents)],
            changeCents: result.changeCents,
            gift: false,
          ),
          config: cfg,
        ),
      );
    } catch (e) {
      _toast('Error al cobrar: $e');
    }
  }

  Future<void> _openDetail(ServiceNote note) async {
    final theme = Theme.of(context);
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final pagada = note.saleId != null;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Nota ${note.folio}',
                        style: theme.textTheme.titleLarge),
                  ),
                  StatusPill(pagada ? 'Cobrada' : 'Pendiente',
                      color: pagada ? AppColors.success : null),
                ],
              ),
              const SizedBox(height: 4),
              Text(df.format(note.createdAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Divider(height: 20),
              _detailRow('Cliente', note.customerName),
              _detailRow('Tipo', serviceItemTypeLabel(note.itemType)),
              if (note.brand != null && note.brand!.isNotEmpty)
                _detailRow('Marca', note.brand!),
              if (note.color != null && note.color!.isNotEmpty)
                _detailRow('Color', note.color!),
              const SizedBox(height: 16),
              if (!pagada)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    _cobrar(note);
                  },
                  icon: const Icon(Icons.point_of_sale),
                  label: const Text('Cobrar'),
                ),
              if (!pagada) const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  _printNote(note);
                },
                icon: const Icon(Icons.ios_share),
                label: const Text('Reimprimir / compartir nota'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yy');
    return Scaffold(
      appBar: AppBar(title: const Text('Notas de servicio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add),
        label: const Text('Nueva nota'),
      ),
      body: FutureBuilder<List<ServiceNote>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snap.data!;
          if (notes.isEmpty) {
            return const EmptyState(
              icon: Icons.design_services_outlined,
              title: 'Sin notas de servicio',
              hint: 'Toca "Nueva nota" al recibir tenis, gorra o bolsa para '
                  'limpieza.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final n = notes[i];
              final pagada = n.saleId != null;
              final sub = [
                serviceItemTypeLabel(n.itemType),
                if (n.brand != null && n.brand!.isNotEmpty) n.brand!,
                if (n.color != null && n.color!.isNotEmpty) n.color!,
              ].join(' · ');
              return SurfaceCard(
                onTap: () => _openDetail(n),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              StatusPill(n.folio),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(n.customerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text(df.format(n.createdAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    StatusPill(pagada ? 'Cobrada' : 'Pendiente',
                        color: pagada ? AppColors.success : null),
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

/// Alta de nota: cliente, tipo (tenis/gorra/bolsa), marca y color.
class _ServiceNoteForm extends StatefulWidget {
  const _ServiceNoteForm({required this.repo});
  final ServiceNoteRepository repo;

  @override
  State<_ServiceNoteForm> createState() => _ServiceNoteFormState();
}

class _ServiceNoteFormState extends State<_ServiceNoteForm> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _color = TextEditingController();
  ServiceItemType _type = ServiceItemType.tenis;
  bool _saving = false;
  String? _error;

  static const _types = [
    ServiceItemType.tenis,
    ServiceItemType.gorra,
    ServiceItemType.bolsa,
  ];

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle el nombre del cliente');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final note = await widget.repo.create(
        customerName: name,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        color: _color.text.trim().isEmpty ? null : _color.text.trim(),
        itemType: _type,
      );
      if (mounted) Navigator.of(context).pop(note);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nueva nota de servicio',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Nombre del cliente'),
            ),
            const SizedBox(height: 12),
            const Text('Tipo', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _types)
                  ChoiceChip(
                    label: Text(serviceItemTypeLabel(t)),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Marca (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _color,
              decoration: const InputDecoration(labelText: 'Color (opcional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Crear nota'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectSaleInput {
  const _DirectSaleInput(this.description, this.amountCents, this.method);
  final String description;
  final int amountCents;
  final PaymentMethod method;
}

/// Cobro de una venta directa (sin productos): descripción, monto y método.
class _DirectSaleForm extends StatefulWidget {
  const _DirectSaleForm({required this.defaultDescription});
  final String defaultDescription;

  @override
  State<_DirectSaleForm> createState() => _DirectSaleFormState();
}

class _DirectSaleFormState extends State<_DirectSaleForm> {
  late final _desc = TextEditingController(text: widget.defaultDescription);
  final _amount = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  static const _methods = [
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.transfer,
  ];

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = ((double.tryParse(_amount.text.trim()) ?? 0) * 100).round();
    if (cents <= 0 || _desc.text.trim().isEmpty) return;
    Navigator.of(context)
        .pop(_DirectSaleInput(_desc.text.trim(), cents, _method));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cobrar servicio', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Monto', prefixText: '\$'),
            ),
            const SizedBox(height: 12),
            AppDropdown<PaymentMethod>(
              label: 'Método de pago',
              value: _method,
              items: [
                for (final m in _methods)
                  DropdownMenuItem(value: m, child: Text(_paymentLabel(m))),
              ],
              onChanged: (v) => setState(() => _method = v ?? _method),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Cobrar'),
            ),
          ],
        ),
      ),
    );
  }
}
