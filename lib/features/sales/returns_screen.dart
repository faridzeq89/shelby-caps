import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/returns_repository.dart';
import '../../data/repositories/sales_repository.dart' show CheckoutLine;
import '../../services/auth_controller.dart';
import 'variant_picker.dart';

String _money(int c) => '\$${(c / 100).toStringAsFixed(2)}';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key});

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final ReturnsRepository _returns = ReturnsRepository(_db);
  late final CatalogRepository _catalog = CatalogRepository(_db);
  final _folioCtrl = TextEditingController();

  Sale? _sale;
  List<ReturnableLine> _lines = [];
  final _qty = <int, int>{}; // lineId -> cantidad a devolver
  final _damaged = <int, bool>{}; // lineId -> dañada

  Profile get _user => context.read<AuthController>().currentUser!;

  @override
  void dispose() {
    _folioCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _find(String folio) async {
    final sale = await _returns.findByFolio(folio);
    if (sale == null) {
      _toast('No se encontró la venta $folio');
      return;
    }
    final lines = await _returns.returnableLines(sale.id);
    setState(() {
      _sale = sale;
      _lines = lines;
      _qty.clear();
      _damaged.clear();
    });
  }

  List<ReturnItem> _selectedItems() => [
        for (final l in _lines)
          if ((_qty[l.line.id] ?? 0) > 0)
            ReturnItem(l.line, _qty[l.line.id]!,
                damaged: _damaged[l.line.id] ?? false),
      ];

  int _refundPreview() {
    var total = 0;
    for (final l in _lines) {
      final q = _qty[l.line.id] ?? 0;
      if (q > 0) {
        total += (l.line.lineTotalCents / l.line.qty).round() * q;
      }
    }
    return total;
  }

  Future<Profile?> _managerAuth() async {
    if (Permissions.canAuthorizeDiscount(_user.role)) return _user;
    final auth = context.read<AuthController>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Autorización de gerente'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'PIN de gerente'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Autorizar')),
        ],
      ),
    );
    if (ok != true) return null;
    return auth.verifyPrivilegedPin(ctrl.text);
  }

  Future<void> _refund() async {
    final items = _selectedItems();
    if (items.isEmpty || _sale == null) {
      _toast('Elige qué devolver');
      return;
    }
    final method = await showDialog<RefundMethod>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Reembolso de ${_money(_refundPreview())}'),
        content: const Text('¿Cómo se devuelve?'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, RefundMethod.creditNote),
              child: const Text('Nota de crédito')),
          FilledButton(
              onPressed: () => Navigator.pop(context, RefundMethod.cash),
              child: const Text('Efectivo')),
        ],
      ),
    );
    if (method == null) return;

    Profile? authorizedBy;
    if (method == RefundMethod.cash) {
      authorizedBy = await _managerAuth();
      if (authorizedBy == null) {
        _toast('Reembolso en efectivo no autorizado');
        return;
      }
    }
    try {
      final r = await _returns.processReturn(
        actor: _user,
        sale: _sale!,
        items: items,
        method: method,
        authorizedBy: authorizedBy,
      );
      if (!mounted) return;
      await _done('Devolución ${r.folio}',
          'Reembolso: ${_money(r.refundCents)}'
          '${r.creditNoteId != null ? '\nNota de crédito generada' : ''}');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _exchange() async {
    final items = _selectedItems();
    if (items.isEmpty || _sale == null) {
      _toast('Elige qué devolver primero');
      return;
    }
    final picked = await pickProductAndVariant(context, _catalog);
    if (picked == null) return;
    final newUnit = effectivePrice(picked.$1, picked.$2);
    final refund = _refundPreview();
    final difference = newUnit - refund;

    var cashTendered = 0;
    if (difference > 0) {
      final paid = await _askPesos(
          'Diferencia a cobrar: ${_money(difference)}\nEfectivo recibido',
          initial: (difference / 100).toStringAsFixed(2));
      if (paid == null) return;
      if (paid < difference) {
        _toast('Efectivo insuficiente');
        return;
      }
      cashTendered = paid;
    }

    try {
      final ex = await _returns.processExchange(
        actor: _user,
        sale: _sale!,
        returnItems: items,
        newLines: [
          CheckoutLine(
              product: picked.$1,
              variant: picked.$2,
              qty: 1,
              unitPriceCents: newUnit),
        ],
        cashTenderedCents: cashTendered,
      );
      if (!mounted) return;
      final diffMsg = ex.differenceCents > 0
          ? 'Cobrado: ${_money(ex.cashCollectedCents)} · Cambio: ${_money(ex.changeCents)}'
          : ex.differenceCents < 0
              ? 'A favor del cliente: ${_money(-ex.differenceCents)} (nota de crédito)'
              : 'Sin diferencia';
      await _done('Cambio ${ex.newFolio}', diffMsg);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<int?> _askPesos(String title, {String initial = '0'}) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
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
              child: const Text('Aceptar')),
        ],
      ),
    );
    if (ok != true) return null;
    final v = double.tryParse(ctrl.text.trim());
    return v == null ? null : (v * 100).round();
  }

  Future<void> _done(String title, String body) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo')),
        ],
      ),
    );
    setState(() {
      _sale = null;
      _lines = [];
      _qty.clear();
      _damaged.clear();
      _folioCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devoluciones y cambios')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _folioCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Folio de la venta (o escanea el ticket) + Enter',
                prefixIcon: Icon(Icons.receipt_long),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _find,
            ),
          ),
          if (_sale != null)
            Expanded(child: _saleDetail())
          else
            const Expanded(
                child: Center(child: Text('Busca una venta por su folio'))),
        ],
      ),
    );
  }

  Widget _saleDetail() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (final l in _lines) _lineTile(l),
            ],
          ),
        ),
        Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _refund,
                    icon: const Icon(Icons.assignment_return),
                    label: const Text('Devolver'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _exchange,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Cambiar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lineTile(ReturnableLine l) {
    final id = l.line.id;
    final selected = _qty[id] ?? 0;
    final title =
        '${l.product.name} ${l.variant.size ?? ''} ${l.variant.color ?? ''}'
            .trim();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Devolvible: ${l.returnable}  ·  '
                '${_money((l.line.lineTotalCents / l.line.qty).round())} c/u'),
            Row(
              children: [
                const Text('Devolver:'),
                IconButton(
                  onPressed: selected > 0
                      ? () => setState(() => _qty[id] = selected - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$selected', style: const TextStyle(fontSize: 18)),
                IconButton(
                  onPressed: selected < l.returnable
                      ? () => setState(() => _qty[id] = selected + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Text('Dañada'),
                    Switch(
                      value: _damaged[id] ?? false,
                      onChanged: (v) => setState(() => _damaged[id] = v),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
