import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/cloud_backup_service.dart';
import 'inventory_variant_picker.dart';

class _ReceiveRow {
  _ReceiveRow(this.product, this.variant);
  final Product product;
  final Variant variant;
  int qty = 1;
  int? costCents; // null => no actualiza el costo de la variante
}

/// Recepción de mercancía: arma una lista de variantes recibidas con su
/// cantidad (y, opcional, el costo de la entrada) y la registra como
/// movimientos `receipt` en el ledger, en una sola transacción.
class ReceiveStockScreen extends StatefulWidget {
  const ReceiveStockScreen({super.key});

  @override
  State<ReceiveStockScreen> createState() => _ReceiveStockScreenState();
}

class _ReceiveStockScreenState extends State<ReceiveStockScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);
  final _reference = TextEditingController();
  final _rows = <_ReceiveRow>[];
  bool _saving = false;

  Profile get _actor => context.read<AuthController>().currentUser!;

  int get _totalPieces => _rows.fold(0, (s, r) => s + r.qty);

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _add() async {
    final picked = await pickInventoryVariant(context, _catalog);
    if (picked == null) return;
    final existing =
        _rows.where((r) => r.variant.id == picked.$2.id).firstOrNull;
    setState(() {
      if (existing != null) {
        existing.qty++;
      } else {
        _rows.add(_ReceiveRow(picked.$1, picked.$2));
      }
    });
  }

  Future<void> _editCost(_ReceiveRow row) async {
    final ctrl = TextEditingController(
        text: row.costCents == null
            ? ''
            : (row.costCents! / 100).toStringAsFixed(2));
    final result = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Costo de la entrada'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Costo unitario',
            prefixText: '\$',
            helperText: 'Actualiza el costo de la variante. Vacío = no cambiar.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(-1),
              child: const Text('Quitar')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) {
                Navigator.of(context).pop(-1);
                return;
              }
              final cents = ((double.tryParse(t) ?? -1) * 100).round();
              Navigator.of(context).pop(cents < 0 ? null : cents);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == null) return; // cancelado / inválido
    setState(() => row.costCents = result < 0 ? null : result);
  }

  Future<void> _confirm() async {
    if (_rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      final locationId = await _inventory.defaultLocationId();
      await _inventory.receiveBatch(
        _actor,
        locationId: locationId,
        lines: [
          for (final r in _rows)
            ReceiptLine(
              variantId: r.variant.id,
              qty: r.qty,
              unitCostCents: r.costCents,
              updateCost: r.costCents != null,
            ),
        ],
        referenceId:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      );
      if (mounted) {
        context.read<CloudBackupService>().backupSoon();
        context.read<CatalogSyncService>().publishSoon();
      }
      if (!mounted) return;
      _toast('Recibidas $_totalPieces piezas en ${_rows.length} variantes');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo recibir: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recepción de mercancía')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _reference,
              decoration: const InputDecoration(
                labelText: 'Referencia (factura / proveedor, opcional)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Agregar variante'),
              ),
            ),
          ),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Text('Agrega las variantes que estás recibiendo.'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _rowTile(_rows[i]),
                  ),
          ),
          _bar(),
        ],
      ),
    );
  }

  Widget _rowTile(_ReceiveRow row) {
    final tc = '${row.variant.size ?? ''} ${row.variant.color ?? ''}'.trim();
    return ListTile(
      title: Text(row.product.name),
      subtitle: Text([
        if (tc.isNotEmpty) tc else row.variant.sku,
        if (row.costCents != null)
          'costo \$${(row.costCents! / 100).toStringAsFixed(2)}',
      ].join('  ·  ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Costo',
            icon: const Icon(Icons.attach_money),
            onPressed: () => _editCost(row),
          ),
          IconButton(
            onPressed: () => setState(() {
              row.qty--;
              if (row.qty <= 0) _rows.remove(row);
            }),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('${row.qty}', style: const TextStyle(fontSize: 18)),
          IconButton(
            onPressed: () => setState(() => row.qty++),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _bar() {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Text('$_totalPieces piezas · ${_rows.length} variantes',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.icon(
              onPressed: (_rows.isEmpty || _saving) ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Recibir'),
            ),
          ],
        ),
      ),
    );
  }
}
