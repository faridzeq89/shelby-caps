import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../services/coupon_service.dart';

/// Administra los **cupones de descuento** de la tienda en línea (porcentaje o
/// monto fijo). Se guardan en Supabase; la tienda los valida al aplicarlos y el
/// cobro (`process-payment`) los aplica de forma autoritativa.
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  late final CouponService _service =
      CouponService(context.read<AppDatabase>());
  late Future<List<Coupon>> _future = _load();

  Future<List<Coupon>> _load() {
    if (!_service.available) {
      return Future.error('Sin conexión a Supabase configurada');
    }
    return _service.list();
  }

  void _reload() => setState(() => _future = _load());

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _edit([Coupon? existing]) async {
    final res = await showDialog<Coupon>(
      context: context,
      builder: (_) => _CouponDialog(existing: existing),
    );
    if (res == null) return;
    try {
      await _service.upsert(
        code: res.code,
        kind: res.kind,
        value: res.value,
        active: res.active,
      );
      _toast('Cupón guardado');
      _reload();
    } catch (e) {
      _toast('No se pudo guardar: $e');
    }
  }

  Future<void> _toggle(Coupon c) async {
    try {
      await _service.upsert(
          code: c.code, kind: c.kind, value: c.value, active: !c.active);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete(Coupon c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar cupón'),
        content: Text('¿Borrar el cupón "${c.code}"? No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(c.code);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  String _label(Coupon c) =>
      c.isPercent ? '${c.value}% de descuento' : '${money(c.value)} de descuento';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cupones de descuento')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cupón'),
      ),
      body: FutureBuilder<List<Coupon>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'No se pudieron cargar los cupones',
              hint: '${snap.error}',
            );
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'Sin cupones',
              hint: 'Toca "Nuevo cupón" para crear un código de descuento para '
                  'la tienda en línea.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = list[i];
              return SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(c.code,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 1)),
                              const SizedBox(width: 8),
                              if (!c.active)
                                StatusPill('Inactivo', color: theme.hintColor),
                            ],
                          ),
                          Text(_label(c),
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(value: c.active, onChanged: (_) => _toggle(c)),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _edit(c),
                    ),
                    IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _delete(c),
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

class _CouponDialog extends StatefulWidget {
  const _CouponDialog({this.existing});
  final Coupon? existing;

  @override
  State<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends State<_CouponDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.existing?.code ?? '');
  late final TextEditingController _value = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!.isPercent
              ? widget.existing!.value.toString()
              : (widget.existing!.value / 100).toStringAsFixed(0)));
  late bool _percent = widget.existing?.isPercent ?? true;
  late bool _active = widget.existing?.active ?? true;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo cupón' : 'Editar cupón'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _code,
              autofocus: true,
              enabled: widget.existing == null, // el código es la llave
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
              decoration: const InputDecoration(
                  labelText: 'Código', hintText: 'Ej. BIENVENIDO'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Porcentaje %')),
                ButtonSegment(value: false, label: Text('Monto fijo \$')),
              ],
              selected: {_percent},
              onSelectionChanged: (s) => setState(() => _percent = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: _percent ? 'Porcentaje' : 'Monto',
                prefixText: _percent ? null : '\$ ',
                suffixText: _percent ? '%' : null,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final code = _code.text.trim().toUpperCase();
            final raw = double.tryParse(_value.text.trim()) ?? 0;
            if (code.isEmpty || raw <= 0) return;
            var value = _percent ? raw.round() : (raw * 100).round();
            if (_percent) value = value.clamp(1, 100);
            Navigator.pop(
              context,
              Coupon(
                code: code,
                kind: _percent ? 'percent' : 'fixed',
                value: value,
                active: _active,
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
