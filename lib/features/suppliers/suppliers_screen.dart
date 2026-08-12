import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/supplier_repository.dart';
import '../../services/auth_controller.dart';

/// Directorio de proveedores: lista, alta y edición.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final SupplierRepository _repo =
      SupplierRepository(context.read<AppDatabase>());
  late Future<List<Supplier>> _future = _repo.all();

  Profile get _actor => context.read<AuthController>().currentUser!;

  void _reload() => setState(() => _future = _repo.all());

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _edit({Supplier? supplier}) async {
    final result = await showModalBottomSheet<_SupplierInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SupplierSheet(supplier: supplier),
    );
    if (result == null) return;
    try {
      if (supplier == null) {
        await _repo.create(
          actor: _actor,
          name: result.name,
          phone: result.phone,
          contact: result.contact,
          notes: result.notes,
        );
        _toast('Proveedor agregado');
      } else {
        await _repo.update(
          actor: _actor,
          id: supplier.id,
          name: result.name,
          phone: result.phone,
          contact: result.contact,
          notes: result.notes,
        );
        _toast('Proveedor actualizado');
      }
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _archive(Supplier s) async {
    try {
      await _repo.setActive(_actor, s.id, false);
      _toast('Proveedor archivado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proveedores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proveedor'),
      ),
      body: FutureBuilder<List<Supplier>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final suppliers = snap.data!;
          if (suppliers.isEmpty) {
            return const EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Sin proveedores',
              hint: 'Toca "Nuevo proveedor" para tener a la mano a quién le '
                  'compras cada producto.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: suppliers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = suppliers[i];
              final sub = [
                if (s.phone != null) s.phone!,
                if (s.contact != null) s.contact!,
              ].join('  ·  ');
              return SurfaceCard(
                onTap: () => _edit(supplier: s),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                      child: const Icon(Icons.local_shipping_outlined,
                          color: AppColors.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          if (sub.isNotEmpty)
                            Text(sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _edit(supplier: s);
                        if (v == 'archive') _archive(s);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(
                            value: 'archive', child: Text('Archivar')),
                      ],
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

class _SupplierInput {
  _SupplierInput(this.name, this.phone, this.contact, this.notes);
  final String name;
  final String? phone;
  final String? contact;
  final String? notes;
}

class _SupplierSheet extends StatefulWidget {
  const _SupplierSheet({this.supplier});
  final Supplier? supplier;

  @override
  State<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends State<_SupplierSheet> {
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _contact =
      TextEditingController(text: widget.supplier?.contact ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _contact.dispose();
    _notes.dispose();
    super.dispose();
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
            Text(widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
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
              controller: _contact,
              decoration:
                  const InputDecoration(labelText: 'Contacto (opcional)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_SupplierInput(
                        _name.text.trim(),
                        _phone.text.trim().isEmpty ? null : _phone.text.trim(),
                        _contact.text.trim().isEmpty
                            ? null
                            : _contact.text.trim(),
                        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                      )),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
