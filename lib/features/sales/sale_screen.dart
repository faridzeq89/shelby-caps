import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/cloud_backup_service.dart';
import '../inventory/inventory_home_screen.dart';
import '../inventory/low_stock_screen.dart';
import 'layaways_screen.dart';
import 'returns_screen.dart';
import 'ticket_service.dart';
import 'variant_picker.dart';

class _CartLine {
  _CartLine(this.product, this.variant, this.unitPriceCents, this.qty);
  final Product product;
  final Variant variant;
  final int unitPriceCents;
  int qty;
  int lineDiscountCents = 0;

  int get lineTotal => unitPriceCents * qty;

  /// Importe de la línea tras su descuento propio.
  int get net => (lineTotal - lineDiscountCents).clamp(0, lineTotal);
  String get title =>
      '${product.name}  ${variant.size ?? ''} ${variant.color ?? ''}'.trim();
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final SalesRepository _sales = SalesRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  final _lines = <_CartLine>[];
  int? _locationId;
  int _lowStock = 0;

  Profile get _cashier => context.read<AuthController>().currentUser!;

  int get _total => _lines.fold(0, (s, l) => s + l.net);
  int get _tax => _lines.fold(
      0, (s, l) => s + taxIncludedBreakdown(l.net, l.product.taxRateBps).taxCents);

  static const _lineAuthThreshold = 0.15; // descuento por línea que exige gerente
  int get _itemCount => _lines.fold(0, (s, l) => s + l.qty);

  @override
  void initState() {
    super.initState();
    _db.select(_db.locations).getSingleOrNull().then((loc) {
      if (mounted) setState(() => _locationId = loc?.id);
    });
    _refreshLowStock();
  }

  Future<void> _refreshLowStock() async {
    final n = await _inventory.lowStockCount();
    if (mounted) setState(() => _lowStock = n);
  }

  Future<void> _openInventory(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    _refreshLowStock();
    _scanFocus.requestFocus();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  void _addVariant(Product product, Variant variant) {
    setState(() {
      final existing =
          _lines.where((l) => l.variant.id == variant.id).firstOrNull;
      if (existing != null) {
        existing.qty++;
      } else {
        _lines.add(_CartLine(
            product, variant, effectivePrice(product, variant), 1));
      }
    });
  }

  Future<void> _onScan(String code) async {
    _scanCtrl.clear();
    _scanFocus.requestFocus();
    if (code.trim().isEmpty) return;
    final variant = await _catalog.resolveByCode(code);
    if (variant == null) {
      _toast('Código "$code" sin resultado');
      return;
    }
    final product = await _catalog.productOfVariant(variant);
    if (product != null) _addVariant(product, variant);
  }

  Future<void> _openSearch() async {
    final picked = await pickProductAndVariant(context, _catalog);
    if (picked != null) _addVariant(picked.$1, picked.$2);
    _scanFocus.requestFocus();
  }

  void _changeQty(_CartLine line, int delta) {
    setState(() {
      line.qty += delta;
      if (line.qty <= 0) _lines.remove(line);
    });
  }

  Future<void> _checkout() async {
    if (_lines.isEmpty || _locationId == null) return;
    final payment = await showModalBottomSheet<_PaymentResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(grossCents: _total),
    );
    if (payment == null) return;

    CheckoutResult result;
    try {
      result = await _sales.checkout(
        cashier: _cashier,
        locationId: _locationId!,
        lines: [
          for (final l in _lines)
            CheckoutLine(
              product: l.product,
              variant: l.variant,
              qty: l.qty,
              unitPriceCents: l.unitPriceCents,
              lineDiscountCents: l.lineDiscountCents,
            ),
        ],
        payments: payment.payments,
        discountCents: payment.discountCents,
        discountReason: payment.discountReason,
      );
    } catch (e) {
      _toast('Error al cobrar: $e');
      return;
    }

    // Respaldo en la nube tras la venta (sin bloquear).
    if (mounted) context.read<CloudBackupService>().backupSoon();

    // La venta YA quedó registrada. La impresión es aparte: si falla, no se
    // pierde la venta.
    final ticket = TicketData(
      folio: result.folio,
      dateTime: DateTime.now(),
      cashierName: _cashier.name,
      lines: [
        for (final l in _lines)
          TicketLine(
            description: l.title,
            qty: l.qty,
            unitPriceCents: l.unitPriceCents,
            lineTotalCents: l.net,
          ),
      ],
      subtotalCents: result.grossCents,
      discountCents: result.discountCents,
      taxCents: result.taxCents,
      totalCents: result.totalCents,
      payments: [
        for (final p in payment.payments) (_methodLabel(p.method), p.amountCents),
      ],
      changeCents: result.changeCents,
      gift: payment.gift,
    );

    var printed = true;
    try {
      await Printing.layoutPdf(
        onLayout: (_) => TicketService.buildPdf(ticket),
        name: 'ticket_${result.folio}',
      );
    } catch (_) {
      printed = false;
    }

    if (!mounted) return;
    await _showDone(result, printed);
    setState(() => _lines.clear());
    _refreshLowStock();
    _scanFocus.requestFocus();
  }

  Future<void> _showDone(CheckoutResult r, bool printed) {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Venta registrada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folio: ${r.folio}'),
            Text('Total: \$${(r.totalCents / 100).toStringAsFixed(2)}'),
            Text('Cambio: \$${(r.changeCents / 100).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (!printed)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('(No se pudo imprimir, pero la venta quedó guardada)'),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venta'),
        actions: [
          IconButton(
            onPressed: () => _openInventory(const LowStockScreen()),
            icon: _lowStock > 0
                ? Badge(
                    label: Text('$_lowStock'),
                    child: const Icon(Icons.notifications_active_outlined),
                  )
                : const Icon(Icons.notifications_none),
            tooltip: 'Stock bajo',
          ),
          IconButton(
            onPressed: () => _openInventory(const InventoryHomeScreen()),
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Inventario',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LayawaysScreen()),
            ),
            icon: const Icon(Icons.bookmark_border),
            tooltip: 'Apartados',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReturnsScreen()),
            ),
            icon: const Icon(Icons.assignment_return_outlined),
            tooltip: 'Devoluciones y cambios',
          ),
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Buscar producto',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _scanCtrl,
              focusNode: _scanFocus,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Escanea un código o busca y toca (+ Enter)',
                prefixIcon: Icon(Icons.qr_code_scanner),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _onScan,
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? const Center(child: Text('Carrito vacío'))
                : ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _cartTile(_lines[i]),
                  ),
          ),
          _summaryBar(),
        ],
      ),
    );
  }

  Widget _cartTile(_CartLine line) {
    final unit = '\$${(line.unitPriceCents / 100).toStringAsFixed(2)}';
    final subtitle = line.lineDiscountCents > 0
        ? '$unit c/u  ·  −\$${(line.lineDiscountCents / 100).toStringAsFixed(2)}  ·  = \$${(line.net / 100).toStringAsFixed(2)}'
        : '$unit c/u  ·  = \$${(line.lineTotal / 100).toStringAsFixed(2)}';
    return ListTile(
      title: Text(line.title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
              tooltip: 'Descuento en línea',
              onPressed: () => _editLineDiscount(line),
              icon: Icon(Icons.local_offer_outlined,
                  color: line.lineDiscountCents > 0
                      ? Theme.of(context).colorScheme.primary
                      : null)),
          IconButton(
              onPressed: () => _changeQty(line, -1),
              icon: const Icon(Icons.remove_circle_outline)),
          Text('${line.qty}', style: const TextStyle(fontSize: 18)),
          IconButton(
              onPressed: () => _changeQty(line, 1),
              icon: const Icon(Icons.add_circle_outline)),
        ],
      ),
    );
  }

  /// Verifica autorización de gerente (o que el actor ya lo sea) por PIN.
  Future<bool> _authorizeManager() async {
    if (Permissions.canAuthorizeDiscount(_cashier.role)) return true;
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Autorizar')),
        ],
      ),
    );
    if (ok != true) return false;
    return (await auth.verifyPrivilegedPin(ctrl.text)) != null;
  }

  Future<void> _editLineDiscount(_CartLine line) async {
    final ctrl = TextEditingController(
        text: line.lineDiscountCents == 0
            ? ''
            : (line.lineDiscountCents / 100).toStringAsFixed(2));
    final pesos = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Descuento — ${line.title}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              prefixText: '\$', labelText: 'Descuento (0 para quitar)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(double.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (pesos == null) return;
    final cents = ((pesos * 100).round()).clamp(0, line.lineTotal);
    if (cents > (line.lineTotal * _lineAuthThreshold).round()) {
      if (!await _authorizeManager()) {
        _toast('Descuento no autorizado');
        return;
      }
    }
    setState(() => line.lineDiscountCents = cents);
  }

  Widget _summaryBar() {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$_itemCount artículos',
                    style: theme.textTheme.bodyMedium),
                Text('IVA \$${(_tax / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: theme.textTheme.titleLarge),
                Text('\$${(_total / 100).toStringAsFixed(2)}',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _lines.isEmpty ? null : _checkout,
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Cobrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ===========================================================================
// Cobro: pago dividido, descuento y ticket de regalo
// ===========================================================================

String _methodLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Efectivo',
      PaymentMethod.card => 'Tarjeta',
      PaymentMethod.transfer => 'Transferencia',
      PaymentMethod.creditNote => 'Nota de crédito',
    };

class _PaymentResult {
  const _PaymentResult({
    required this.payments,
    required this.discountCents,
    required this.discountReason,
    required this.gift,
  });
  final List<PaymentInput> payments;
  final int discountCents;
  final String? discountReason;
  final bool gift;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.grossCents});
  final int grossCents;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  // Umbral que exige PIN de gerente.
  static const _authThreshold = 0.15;

  late final _cash = TextEditingController(
      text: (widget.grossCents / 100).toStringAsFixed(2));
  final _card = TextEditingController(text: '0');
  final _transfer = TextEditingController(text: '0');
  final _discount = TextEditingController(text: '0');
  final _reason = TextEditingController();
  bool _gift = false;
  bool _authorized = false;

  int _cents(TextEditingController c) =>
      ((double.tryParse(c.text.trim()) ?? 0) * 100).round();

  int get _discountCents => _cents(_discount).clamp(0, widget.grossCents);
  int get _net => widget.grossCents - _discountCents;
  int get _nonCash => _cents(_card) + _cents(_transfer);
  int get _entered => _cents(_cash) + _nonCash;
  int get _change => _entered - _net;
  bool get _needsAuth =>
      _discountCents > (widget.grossCents * _authThreshold).round();
  bool get _canConfirm => _nonCash <= _net && _entered >= _net;

  @override
  void dispose() {
    _cash.dispose();
    _card.dispose();
    _transfer.dispose();
    _discount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<bool> _authorize() async {
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Autorizar')),
        ],
      ),
    );
    if (ok != true) return false;
    return (await auth.verifyPrivilegedPin(ctrl.text)) != null;
  }

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    if (_discountCents > 0 && _needsAuth && !_authorized) {
      final role = context.read<AuthController>().currentUser!.role;
      if (Permissions.canAuthorizeDiscount(role)) {
        _authorized = true; // admin/gerente ya está autorizado
      } else {
        final ok = await _authorize();
        if (!ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('PIN de gerente inválido o cancelado')));
          }
          return;
        }
        _authorized = true;
      }
    }
    final payments = <PaymentInput>[
      if (_cents(_cash) > 0) PaymentInput(PaymentMethod.cash, _cents(_cash)),
      if (_cents(_card) > 0) PaymentInput(PaymentMethod.card, _cents(_card)),
      if (_cents(_transfer) > 0)
        PaymentInput(PaymentMethod.transfer, _cents(_transfer)),
    ];
    if (!mounted) return;
    Navigator.of(context).pop(_PaymentResult(
      payments: payments,
      discountCents: _discountCents,
      discountReason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      gift: _gift,
    ));
  }

  Widget _amountField(String label, TextEditingController c) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: '\$'),
        onChanged: (_) => setState(() {}),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text('A cobrar: \$${(_net / 100).toStringAsFixed(2)}',
                style: theme.textTheme.titleLarge),
            if (_discountCents > 0)
              Text('Bruto \$${(widget.grossCents / 100).toStringAsFixed(2)}  ·  '
                  'descuento \$${(_discountCents / 100).toStringAsFixed(2)}'
                  '${_needsAuth ? '  (requiere gerente)' : ''}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _amountField('Descuento', _discount)),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _reason,
                    decoration:
                        const InputDecoration(labelText: 'Motivo (opcional)'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _amountField('Efectivo', _cash),
            const SizedBox(height: 8),
            _amountField('Tarjeta', _card),
            const SizedBox(height: 8),
            _amountField('Transferencia', _transfer),
            const SizedBox(height: 12),
            Text(
              _change >= 0
                  ? 'Cambio: \$${(_change / 100).toStringAsFixed(2)}'
                  : 'Falta \$${(-_change / 100).toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                  color: _change < 0 ? theme.colorScheme.error : null),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ticket de regalo (sin precios)'),
              value: _gift,
              onChanged: (v) => setState(() => _gift = v),
            ),
            FilledButton.icon(
              onPressed: _canConfirm ? _confirm : null,
              icon: const Icon(Icons.check),
              label: const Text('Cobrar e imprimir'),
            ),
          ],
        ),
      ),
    );
  }
}
