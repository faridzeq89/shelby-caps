import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/customer_repository.dart';

String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Admin → Clientes: lista con búsqueda, alta/edición y ficha con historial.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late final CustomerRepository _repo =
      CustomerRepository(context.read<AppDatabase>());
  List<Customer> _customers = [];
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list =
        _query.trim().isEmpty ? await _repo.all() : await _repo.search(_query);
    if (mounted) setState(() => _customers = list);
  }

  void _onSearch(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _load);
  }

  Future<void> _openEditor({Customer? existing}) async {
    final saved = await showCustomerEditor(context, _repo, existing: existing);
    if (saved != null) _load();
  }

  Future<void> _openDetail(Customer c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CustomerDetailScreen(customerId: c.id)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nuevo cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o teléfono',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearch,
            ),
          ),
          Expanded(
            child: _customers.isEmpty
                ? const Center(child: Text('Sin clientes'))
                : ListView.separated(
                    itemCount: _customers.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _customers[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(_initials(c.name))),
                        title: Text(c.name),
                        subtitle: c.phone != null ? Text(c.phone!) : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openDetail(c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts[1].characters.first)
      .toUpperCase();
}

/// Ficha del cliente: datos + totales + historial de compras.
class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final CustomerRepository _repo =
      CustomerRepository(context.read<AppDatabase>());
  Customer? _customer;
  CustomerStats? _stats;
  List<Sale> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await _repo.byId(widget.customerId);
    final s = await _repo.stats(widget.customerId);
    final h = await _repo.history(widget.customerId);
    if (mounted) {
      setState(() {
        _customer = c;
        _stats = s;
        _history = h;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _stats;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved =
                  await showCustomerEditor(context, _repo, existing: c);
              if (saved != null) _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.phone != null || c.email != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.phone != null)
                      Row(children: [
                        const Icon(Icons.phone_outlined, size: 18),
                        const SizedBox(width: 8),
                        Text(c.phone!),
                      ]),
                    if (c.email != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.mail_outline, size: 18),
                        const SizedBox(width: 8),
                        Text(c.email!),
                      ]),
                    ],
                    if (c.notes != null && c.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(c.notes!,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (s != null)
            Row(
              children: [
                _statCard(context, 'Compras', '${s.visits}'),
                const SizedBox(width: 10),
                _statCard(context, 'Gastado', _money(s.spentCents)),
                const SizedBox(width: 10),
                _statCard(
                    context,
                    'Última',
                    s.lastVisit == null
                        ? '—'
                        : DateFormat('dd/MM/yy').format(s.lastVisit!)),
              ],
            ),
          const SizedBox(height: 16),
          Text('Historial de compras',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Sin compras registradas')),
            )
          else
            ..._history.map((sale) => Card(
                  child: ListTile(
                    title: Text(sale.folio),
                    subtitle: Text(
                        '${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}'
                        '${sale.status == SaleStatus.cancelled ? '  ·  cancelada' : ''}'),
                    trailing: Text(_money(sale.totalCents),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Editor de alta/edición de cliente. Devuelve el id del cliente guardado, o
/// `null` si se canceló.
Future<int?> showCustomerEditor(BuildContext context, CustomerRepository repo,
    {Customer? existing}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CustomerEditorDialog(repo: repo, existing: existing),
  );
}

class _CustomerEditorDialog extends StatefulWidget {
  const _CustomerEditorDialog({required this.repo, this.existing});
  final CustomerRepository repo;
  final Customer? existing;

  @override
  State<_CustomerEditorDialog> createState() => _CustomerEditorDialogState();
}

class _CustomerEditorDialogState extends State<_CustomerEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    int id;
    if (widget.existing == null) {
      id = await widget.repo.create(
        name: _name.text.trim(),
        phone: _clean(_phone),
        email: _clean(_email),
        notes: _clean(_notes),
      );
    } else {
      id = widget.existing!.id;
      await widget.repo.update(
        id: id,
        name: _name.text.trim(),
        phone: _clean(_phone),
        email: _clean(_email),
        notes: _clean(_notes),
      );
    }
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo cliente' : 'Editar cliente'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration:
                  const InputDecoration(labelText: 'Correo (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Selector de cliente para la venta: buscar, elegir o crear al vuelo.
Future<Customer?> pickCustomer(
    BuildContext context, CustomerRepository repo) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerPickerSheet(repo: repo),
  );
}

class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({required this.repo});
  final CustomerRepository repo;

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  List<Customer> _results = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    widget.repo.all(limit: 30).then((r) {
      if (mounted) setState(() => _results = r);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final r = q.trim().isEmpty
          ? await widget.repo.all(limit: 30)
          : await widget.repo.search(q);
      if (mounted) setState(() => _results = r);
    });
  }

  Future<void> _createNew() async {
    final id = await showCustomerEditor(context, widget.repo);
    if (id == null || !mounted) return;
    final created = await widget.repo.byId(id);
    if (created != null && mounted) Navigator.of(context).pop(created);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 12,
        right: 12,
        top: 12,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar cliente (nombre o teléfono)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _createNew,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Nuevo cliente'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final c = _results[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text(_initials(c.name))),
                    title: Text(c.name),
                    subtitle: c.phone != null ? Text(c.phone!) : null,
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
