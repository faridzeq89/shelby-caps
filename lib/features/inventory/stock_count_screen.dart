import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/cloud_backup_service.dart';
import 'inventory_variant_picker.dart';

/// Conteo físico: se abre una sesión, se escanea/captura lo contado por
/// variante, se ve el reporte de diferencias contra el sistema y se aplica en
/// lote como movimientos `count`. La existencia del sistema queda igual a lo
/// contado.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key});

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);

  int? _countId;
  List<CountLineView> _lines = [];
  bool _loading = true;
  bool _busy = false;

  Profile get _actor => context.read<AuthController>().currentUser!;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final open = await _inventory.openCount();
    final id = open?.id ?? await _inventory.createCount(_actor);
    final lines = await _inventory.countLines(id);
    if (!mounted) return;
    setState(() {
      _countId = id;
      _lines = lines;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    if (_countId == null) return;
    final lines = await _inventory.countLines(_countId!);
    if (mounted) setState(() => _lines = lines);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addOrEdit({Product? product, Variant? variant}) async {
    var p = product;
    var v = variant;
    if (v == null) {
      final picked = await pickInventoryVariant(context, _catalog);
      if (picked == null) return;
      p = picked.$1;
      v = picked.$2;
    }
    if (!mounted) return;
    final counted = await showDialog<int>(
      context: context,
      builder: (_) => _CountedQtyDialog(product: p!, variant: v!),
    );
    if (counted == null || _countId == null) return;
    await _inventory.setCountLine(_countId!, v.id, counted);
    await _refresh();
  }

  Future<void> _apply() async {
    if (_countId == null) return;
    final withDiff = _lines.where((l) => l.difference != 0).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aplicar conteo'),
        content: Text(_lines.isEmpty
            ? 'No hay nada capturado.'
            : 'Se ajustarán $withDiff variantes con diferencia. '
                'El resto queda igual. Esta acción queda en el ledger.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final adjusted = await _inventory.applyCount(_actor, _countId!);
      if (mounted) {
        context.read<CloudBackupService>().backupSoon();
        context.read<CatalogSyncService>().publishSoon();
      }
      if (!mounted) return;
      _toast('Conteo aplicado: $adjusted variantes ajustadas');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('No se pudo aplicar: $e');
      }
    }
  }

  Future<void> _cancel() async {
    if (_countId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar conteo'),
        content: const Text('Se descarta lo capturado sin tocar el stock.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Descartar')),
        ],
      ),
    );
    if (ok != true) return;
    await _inventory.cancelCount(_actor, _countId!);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final withDiff = _lines.where((l) => l.difference != 0).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conteo físico'),
        actions: [
          if (!_loading)
            IconButton(
              tooltip: 'Descartar conteo',
              onPressed: _busy ? null : _cancel,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : () => _addOrEdit(),
              icon: const Icon(Icons.add),
              label: const Text('Contar variante'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _lines.isEmpty
                      ? const Center(
                          child: Text(
                              'Escanea o busca cada variante y captura lo contado.'))
                      : ListView.separated(
                          itemCount: _lines.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) => _lineTile(_lines[i]),
                        ),
                ),
                _bar(withDiff),
              ],
            ),
    );
  }

  Widget _lineTile(CountLineView l) {
    final diff = l.difference;
    final tc = '${l.variant.size ?? ''} ${l.variant.color ?? ''}'.trim();
    final color = diff == 0
        ? Colors.grey
        : (diff > 0 ? AppColors.success : Theme.of(context).colorScheme.error);
    return ListTile(
      title: Text(l.product.name),
      subtitle: Text('${tc.isEmpty ? l.variant.sku : tc}  ·  '
          'sistema ${l.line.systemQty} → contado ${l.line.countedQty}'),
      trailing: Text(
        diff == 0 ? '=' : '${diff > 0 ? '+' : ''}$diff',
        style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: color),
      ),
      onTap: () => _addOrEdit(product: l.product, variant: l.variant),
    );
  }

  Widget _bar(int withDiff) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                  '${_lines.length} contadas · $withDiff con diferencia',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.icon(
              onPressed: (_lines.isEmpty || _busy) ? null : _apply,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountedQtyDialog extends StatefulWidget {
  const _CountedQtyDialog({required this.product, required this.variant});
  final Product product;
  final Variant variant;

  @override
  State<_CountedQtyDialog> createState() => _CountedQtyDialogState();
}

class _CountedQtyDialogState extends State<_CountedQtyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc =
        '${widget.variant.size ?? ''} ${widget.variant.color ?? ''}'.trim();
    return AlertDialog(
      title: Text(widget.product.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tc.isEmpty ? widget.variant.sku : tc),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Piezas contadas'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final n = int.tryParse(_ctrl.text.trim());
            if (n == null || n < 0) return;
            Navigator.of(context).pop(n);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
