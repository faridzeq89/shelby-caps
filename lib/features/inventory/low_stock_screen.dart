import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/auth_controller.dart';

/// Lista de variantes bajo su mínimo (la campana de reorden). Permite fijar el
/// mínimo por variante y el default global de la tienda.
class LowStockScreen extends StatefulWidget {
  const LowStockScreen({super.key});

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockData {
  _LowStockData(this.items, this.defaultMin);
  final List<LowStockItem> items;
  final int defaultMin;
}

class _LowStockScreenState extends State<LowStockScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final InventoryRepository _inventory = InventoryRepository(_db);
  late Future<_LowStockData> _future = _load();

  Profile get _actor => context.read<AuthController>().currentUser!;
  bool get _canEdit => Permissions.canManageInventory(_actor.role);

  Future<_LowStockData> _load() async {
    final items = await _inventory.lowStockVariants();
    final def = await _inventory.lowStockDefault();
    return _LowStockData(items, def);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _editDefault(int current) async {
    final ctrl = TextEditingController(text: current.toString());
    final n = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mínimo global'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Piezas',
            helperText: 'Se usa cuando la variante no tiene su propio mínimo.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < 0) return;
              Navigator.of(context).pop(v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (n == null) return;
    await _inventory.setLowStockDefault(_actor, n);
    _reload();
  }

  Future<void> _editVariantMin(LowStockItem item) async {
    final ctrl = TextEditingController(
        text: item.variant.minStock?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Mínimo de ${item.product.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Mínimo de la variante',
            helperText: 'Vacío = usar el mínimo global. 0 = sin alerta.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(-1),
              child: const Text('Usar global')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                Navigator.of(context).pop(-1);
                return;
              }
              final v = int.tryParse(t);
              if (v == null || v < 0) return;
              Navigator.of(context).pop(v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _inventory.setVariantMinStock(
        _actor, item.variant.id, result < 0 ? null : result);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock bajo')),
      body: FutureBuilder<_LowStockData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return Column(
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Mínimo global'),
                subtitle: Text('${data.defaultMin} piezas'),
                trailing: _canEdit
                    ? TextButton(
                        onPressed: () => _editDefault(data.defaultMin),
                        child: const Text('Cambiar'))
                    : null,
              ),
              const Divider(height: 1),
              Expanded(
                child: data.items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Todo en orden: nada bajo mínimo.',
                              textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.separated(
                        itemCount: data.items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _tile(data.items[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(LowStockItem item) {
    final tc =
        '${item.variant.size ?? ''} ${item.variant.color ?? ''}'.trim();
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.errorContainer,
        child: Text('${item.available}',
            style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold)),
      ),
      title: Text(item.product.name),
      subtitle: Text('${tc.isEmpty ? item.variant.sku : tc}  ·  '
          'disponible ${item.available} / mínimo ${item.threshold}'
          '${item.variant.minStock == null ? ' (global)' : ''}'),
      trailing: _canEdit
          ? IconButton(
              tooltip: 'Ajustar mínimo',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editVariantMin(item),
            )
          : null,
    );
  }
}
