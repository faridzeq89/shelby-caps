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

/// Lee un precio escrito a mano y lo devuelve en centavos. Vacío => `null`, que
/// aquí significa **por definir** (la pieza se recibe y el precio se acuerda
/// después). Basura => `null` también, pero quien llama distingue los dos casos
/// mirando si el texto estaba vacío: un precio mal escrito no se traga en
/// silencio, porque es lo que el cliente va a pagar.
int? precioEnCentavos(String texto) {
  final limpio = texto.trim().replaceAll(',', '');
  if (limpio.isEmpty) return null;
  final pesos = double.tryParse(limpio);
  if (pesos == null || pesos < 0) return null;
  return (pesos * 100).round();
}

/// Notas de servicio (limpieza de tenis/gorra/bolsos): crear, ver pendientes y
/// cobrar.
///
/// La nota es el **papel que se lleva el cliente**: datos del negocio (de
/// fábrica), datos del cliente, información del artículo, costo del servicio y
/// notas adicionales. El costo impreso es lo cotizado — ahí no se cobra. El
/// cobro se hace desde aquí cuando el cliente recoge: es una venta directa (sin
/// productos) que confirma el precio, liga la nota y la marca pagada.
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
    final defaultDesc = 'Servicio ${note.folio}: ${note.qty} '
        '${serviceItemTypeLabel(note.itemType)} — ${note.customerName}';
    final input = await showModalBottomSheet<_DirectSaleInput>(
      context: context,
      isScrollControlled: true,
      // El monto llega ya escrito con el precio cotizado en la nota: es lo que
      // se le prometió al cliente, y volver a teclearlo es donde se cobra de
      // más o de menos. Se puede cambiar (un servicio salió más caro de lo
      // acordado y el cliente aceptó).
      builder: (_) => _DirectSaleForm(
        defaultDescription: defaultDesc,
        defaultAmountCents: note.priceCents,
      ),
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

  /// Corregir la nota: mismo formulario del alta, con los datos ya puestos.
  Future<void> _editar(ServiceNote note) async {
    final actualizada = await showModalBottomSheet<ServiceNote>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ServiceNoteForm(repo: _repo, note: note),
    );
    if (actualizada == null) return;
    _reload();
    if (!mounted) return;
    // Se reimprime en el momento: la nota que tiene el cliente en la mano ya
    // quedó vieja, y es la que va a presentar al recoger su pieza.
    await _printNote(actualizada);
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
              if (note.customerPhone != null && note.customerPhone!.isNotEmpty)
                _detailRow('WhatsApp', note.customerPhone!),
              _detailRow('Artículo', serviceItemTypeLabel(note.itemType)),
              if (note.brand != null && note.brand!.isNotEmpty)
                _detailRow('Marca', note.brand!),
              if (note.size != null && note.size!.isNotEmpty)
                _detailRow('Talla', note.size!),
              if (note.color != null && note.color!.isNotEmpty)
                _detailRow('Color', note.color!),
              _detailRow('Cantidad', '${note.qty}'),
              _detailRow('Costo',
                  note.priceCents == null
                      ? 'Por definir'
                      : money(note.priceCents!)),
              if (note.notes != null && note.notes!.isNotEmpty)
                _detailRow('Notas', note.notes!),
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
              // Se puede corregir incluso ya cobrada: el precio o la nota del
              // estado de la pieza se capturan con el cliente enfrente y se
              // equivocan; volver a capturar la nota perdería su folio.
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  _editar(note);
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Corregir la nota'),
              ),
              const SizedBox(height: 8),
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
                n.qty > 1
                    ? '${n.qty} × ${serviceItemTypeLabel(n.itemType)}'
                    : serviceItemTypeLabel(n.itemType),
                if (n.brand != null && n.brand!.isNotEmpty) n.brand!,
                if (n.size != null && n.size!.isNotEmpty)
                  'talla ${n.size!}',
                if (n.color != null && n.color!.isNotEmpty) n.color!,
                // "Sin precio" a la vista: es lo que hay que acordar antes de
                // que el cliente vuelva por su pieza.
                n.priceCents == null ? 'sin precio' : money(n.priceCents!),
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

/// Captura de la nota, con la forma que pidió el cliente el 20 ago 2026: datos
/// del cliente, información del artículo, costo del servicio y notas.
///
/// Un solo formulario sirve para **crear y para corregir** ([note] nulo = alta):
/// son los mismos campos, y tener dos pantallas gemelas garantiza que un día una
/// se queda sin el campo que se agregó en la otra. Devuelve la nota guardada.
class _ServiceNoteForm extends StatefulWidget {
  const _ServiceNoteForm({required this.repo, this.note});
  final ServiceNoteRepository repo;
  final ServiceNote? note;

  @override
  State<_ServiceNoteForm> createState() => _ServiceNoteFormState();
}

class _ServiceNoteFormState extends State<_ServiceNoteForm> {
  late final _name = TextEditingController(text: _n?.customerName ?? '');
  late final _phone = TextEditingController(text: _n?.customerPhone ?? '');
  late final _brand = TextEditingController(text: _n?.brand ?? '');
  late final _size = TextEditingController(text: _n?.size ?? '');
  late final _color = TextEditingController(text: _n?.color ?? '');
  late final _qty = TextEditingController(text: '${_n?.qty ?? 1}');
  late final _price = TextEditingController(
      text: _n?.priceCents == null
          ? ''
          : (_n!.priceCents! / 100).toStringAsFixed(2));
  late final _notes = TextEditingController(text: _n?.notes ?? '');
  late ServiceItemType _type = _n?.itemType ?? ServiceItemType.tenis;
  bool _saving = false;
  String? _error;

  ServiceNote? get _n => widget.note;
  bool get _editando => widget.note != null;

  static const _types = [
    ServiceItemType.tenis,
    ServiceItemType.gorra,
    ServiceItemType.bolsa,
  ];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _brand.dispose();
    _size.dispose();
    _color.dispose();
    _qty.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponle el nombre del cliente');
      return;
    }
    // Vacío = por definir, y así se imprime. Un costo mal escrito sí se reclama:
    // es lo que el cliente va a pagar.
    final precio = precioEnCentavos(_price.text);
    if (precio == null && _price.text.trim().isNotEmpty) {
      setState(() => _error = 'El costo no se entiende. Déjalo vacío si aún '
          'no lo acuerdas.');
      return;
    }
    final cantidad = int.tryParse(_qty.text.trim()) ?? 0;
    if (cantidad < 1) {
      setState(() => _error = 'La cantidad va de 1 en adelante');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editando) {
        await widget.repo.updateDetails(
          _n!.id,
          customerName: name,
          customerPhone: _phone.text,
          brand: _brand.text,
          size: _size.text,
          color: _color.text,
          itemType: _type,
          qty: cantidad,
          priceCents: precio,
          notes: _notes.text,
        );
        final v = await widget.repo.byId(_n!.id);
        if (mounted) Navigator.of(context).pop(v);
      } else {
        final nota = await widget.repo.create(
          customerName: name,
          customerPhone: _phone.text,
          brand: _brand.text,
          size: _size.text,
          color: _color.text,
          itemType: _type,
          qty: cantidad,
          priceCents: precio,
          notes: _notes.text,
        );
        if (mounted) Navigator.of(context).pop(nota);
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  Widget _titulo(String texto) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: Text(texto,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.4,
                color: AppColors.accent)),
      );

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
            Text(_editando ? 'Nota ${_n!.folio}' : 'Nueva nota de servicio',
                style: Theme.of(context).textTheme.titleLarge),
            // Los datos del negocio (WhatsApp y ubicación) no se piden aquí: van
            // impresos solos, desde Ajustes → Impresoras y tickets.
            _titulo('DATOS DEL CLIENTE'),
            TextField(
              controller: _name,
              autofocus: !_editando,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                helperText: 'Para avisarle cuando esté lista su pieza',
              ),
            ),
            _titulo('INFORMACIÓN DEL ARTÍCULO'),
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
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Marca'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _size,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Talla'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _color,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Color'),
            ),
            _titulo('COSTO DEL SERVICIO'),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Costo',
                prefixText: '\$',
                helperText: 'Déjalo vacío si lo vas a acordar después. Aquí no '
                    'se cobra: el cobro es aparte.',
              ),
            ),
            _titulo('NOTAS ADICIONALES'),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notas',
                helperText: 'Cómo llegó la pieza: manchas, suela despegada…',
                alignLabelWithHint: true,
              ),
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
              label: Text(_editando ? 'Guardar y reimprimir' : 'Crear nota'),
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
  const _DirectSaleForm(
      {required this.defaultDescription, this.defaultAmountCents});
  final String defaultDescription;

  /// Precio cotizado en la nota, si ya se acordó. Nulo => el campo abre vacío.
  final int? defaultAmountCents;

  @override
  State<_DirectSaleForm> createState() => _DirectSaleFormState();
}

class _DirectSaleFormState extends State<_DirectSaleForm> {
  late final _desc = TextEditingController(text: widget.defaultDescription);
  late final _amount = TextEditingController(
      text: widget.defaultAmountCents == null
          ? ''
          : (widget.defaultAmountCents! / 100).toStringAsFixed(2));
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
