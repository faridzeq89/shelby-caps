import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import 'ticket_service.dart';

class _CartLine {
  _CartLine(this.product, this.variant, this.unitPriceCents, this.qty);
  final Product product;
  final Variant variant;
  final int unitPriceCents;
  int qty;

  int get lineTotal => unitPriceCents * qty;
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
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  final _lines = <_CartLine>[];
  int? _locationId;

  Profile get _cashier => context.read<AuthController>().currentUser!;

  int get _total => _lines.fold(0, (s, l) => s + l.lineTotal);
  int get _tax => _lines.fold(
      0, (s, l) => s + taxIncludedBreakdown(l.lineTotal, l.product.taxRateBps).taxCents);
  int get _subtotal => _total - _tax;
  int get _itemCount => _lines.fold(0, (s, l) => s + l.qty);

  @override
  void initState() {
    super.initState();
    _db.select(_db.locations).getSingleOrNull().then((loc) {
      if (mounted) setState(() => _locationId = loc?.id);
    });
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
    final picked = await showModalBottomSheet<(Product, Variant)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SearchSheet(catalog: _catalog),
    );
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
      builder: (_) => _PaymentSheet(totalCents: _total),
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
            ),
        ],
        method: PaymentMethod.cash,
        amountTenderedCents: payment.tenderedCents,
      );
    } catch (e) {
      _toast('Error al cobrar: $e');
      return;
    }

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
            lineTotalCents: l.lineTotal,
          ),
      ],
      subtotalCents: _subtotal,
      taxCents: _tax,
      totalCents: result.totalCents,
      tenderedCents: payment.tenderedCents,
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
    return ListTile(
      title: Text(line.title),
      subtitle: Text(
          '\$${(line.unitPriceCents / 100).toStringAsFixed(2)} c/u  ·  = \$${(line.lineTotal / 100).toStringAsFixed(2)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
// Búsqueda de productos (para agregar tocando)
// ===========================================================================

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.catalog});
  final CatalogRepository catalog;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<(Product, Variant)> _results = [];

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final r = await widget.catalog.searchVariants(q);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 12,
          right: 12,
          top: 12),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o SKU',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final (product, variant) = _results[i];
                  final price = effectivePrice(product, variant);
                  return ListTile(
                    title: Text(
                        '${product.name}  ${variant.size ?? ''} ${variant.color ?? ''}'
                            .trim()),
                    subtitle: Text('SKU ${variant.sku}'),
                    trailing:
                        Text('\$${(price / 100).toStringAsFixed(2)}'),
                    onTap: () => Navigator.of(context).pop((product, variant)),
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

// ===========================================================================
// Cobro en efectivo
// ===========================================================================

class _PaymentResult {
  const _PaymentResult(this.tenderedCents, this.gift);
  final int tenderedCents;
  final bool gift;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.totalCents});
  final int totalCents;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late final TextEditingController _tendered = TextEditingController(
      text: (widget.totalCents / 100).toStringAsFixed(2));
  bool _gift = false;

  int get _tenderedCents =>
      ((double.tryParse(_tendered.text.trim()) ?? 0) * 100).round();
  int get _change => _tenderedCents - widget.totalCents;

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Total a cobrar: \$${(widget.totalCents / 100).toStringAsFixed(2)}',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _tendered,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Efectivo recibido', prefixText: '\$'),
            onChanged: (_) => setState(() {}),
          ),
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
            onPressed: _change < 0
                ? null
                : () => Navigator.of(context)
                    .pop(_PaymentResult(_tenderedCents, _gift)),
            icon: const Icon(Icons.check),
            label: const Text('Cobrar e imprimir'),
          ),
        ],
      ),
    );
  }
}
