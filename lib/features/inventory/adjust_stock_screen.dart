import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/cloud_backup_service.dart';
import 'inventory_variant_picker.dart';

/// Ajuste manual de stock con motivo obligatorio (merma, dañado, robo,
/// corrección). Registra un movimiento `adjustment` con signo. No edita el
/// ledger: agrega una corrección auditable.
class AdjustStockScreen extends StatefulWidget {
  const AdjustStockScreen({super.key});

  @override
  State<AdjustStockScreen> createState() => _AdjustStockScreenState();
}

class _AdjustStockScreenState extends State<AdjustStockScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);
  final _note = TextEditingController();

  Product? _product;
  Variant? _variant;
  int _onHand = 0;
  int _delta = 0; // con signo
  AdjustmentReason _reason = AdjustmentReason.loss;
  bool _saving = false;

  Profile get _actor => context.read<AuthController>().currentUser!;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pick() async {
    final picked = await pickInventoryVariant(context, _catalog);
    if (picked == null) return;
    final stock = await _inventory.stockFor(picked.$2.id);
    if (!mounted) return;
    setState(() {
      _product = picked.$1;
      _variant = picked.$2;
      _onHand = stock.onHand;
      _delta = 0;
    });
  }

  Future<void> _confirm() async {
    final v = _variant;
    if (v == null || _delta == 0) return;
    setState(() => _saving = true);
    try {
      final locationId = await _inventory.defaultLocationId();
      await _inventory.adjust(
        _actor,
        variantId: v.id,
        locationId: locationId,
        qty: _delta,
        reason: _reason,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) {
        context.read<CloudBackupService>().backupSoon();
        context.read<CatalogSyncService>().publishSoon();
      }
      // Nos quedamos en Ajuste: refrescamos la existencia y limpiamos para
      // seguir ajustando (misma variante u otra) sin salir de la pantalla.
      final applied = _delta;
      final stock = await _inventory.stockFor(v.id);
      if (!mounted) return;
      setState(() {
        _onHand = stock.onHand;
        _delta = 0;
        _saving = false;
      });
      _note.clear();
      _toast('Ajuste aplicado: ${applied > 0 ? '+' : ''}$applied · '
          'existencia: ${stock.onHand}');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('No se pudo ajustar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resulting = _onHand + _delta;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajuste de inventario')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_product?.name ?? 'Elige una variante'),
              subtitle: _variant == null
                  ? const Text('Escanea o busca')
                  : Text(
                      '${'${_variant!.size ?? ''} ${_variant!.color ?? ''}'.trim()}  ·  '
                      'existencia actual: $_onHand'),
              trailing: TextButton(
                onPressed: _saving ? null : _pick,
                child: Text(_variant == null ? 'Elegir' : 'Cambiar'),
              ),
            ),
          ),
          if (_variant != null) ...[
            const SizedBox(height: 16),
            Text('Motivo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final r in AdjustmentReason.values)
                  ChoiceChip(
                    label: Text(r.label),
                    selected: _reason == r,
                    onSelected: (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Cantidad a ajustar', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
                'Negativo saca piezas (merma/robo); positivo agrega (corrección).',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  iconSize: 32,
                  onPressed: () => setState(() => _delta--),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    '${_delta > 0 ? '+' : ''}$_delta',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton.filledTonal(
                  iconSize: 32,
                  onPressed: () => setState(() => _delta++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Existencia resultante: $resulting',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: resulting < 0 ? theme.colorScheme.error : null,
                  )),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: (_delta == 0 || _saving) ? null : _confirm,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Aplicar ajuste'),
            ),
          ],
        ],
      ),
    );
  }
}
