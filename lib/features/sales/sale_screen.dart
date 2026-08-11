import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/gift_card_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/loyalty_repository.dart';
import '../../data/repositories/quote_repository.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/image_service.dart';
import '../customers/customers_screen.dart';
import '../inventory/inventory_home_screen.dart';
import '../inventory/low_stock_screen.dart';
import '../scan/scanner_screen.dart';
import 'gift_cards_screen.dart';
import 'layaways_screen.dart';
import 'quotes_screen.dart';
import 'returns_screen.dart';
import 'ticket_service.dart';
import 'variant_picker.dart';

class _CartLine {
  _CartLine(this.product, this.variant, this.retailUnitPriceCents, this.qty)
      : unitPriceCents = retailUnitPriceCents;
  final Product product;
  final Variant variant;

  /// Precio normal (menudeo) de la variante: no cambia con la cantidad.
  final int retailUnitPriceCents;

  /// Precio unitario **efectivo**: menudeo o mayoreo. Lo recalcula [_reprice].
  int unitPriceCents;

  /// True cuando el precio unitario cayó a un escalón de mayoreo.
  bool wholesaleApplied = false;

  int qty;
  int lineDiscountCents = 0;

  int get lineTotal => unitPriceCents * qty;

  /// Importe de la línea tras su descuento propio.
  int get net => (lineTotal - lineDiscountCents).clamp(0, lineTotal);
  String get title =>
      '${product.name}  ${variant.size ?? ''} ${variant.color ?? ''}'.trim();
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key, this.onMenu});

  /// Si se provee, muestra la hamburguesa que abre el menú del shell.
  final VoidCallback? onMenu;

  @override
  State<SaleScreen> createState() => SaleScreenState();
}

class SaleScreenState extends State<SaleScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final SalesRepository _sales = SalesRepository(_db);
  late final InventoryRepository _inventory = InventoryRepository(_db);
  late final CustomerRepository _customers = CustomerRepository(_db);
  late final LoyaltyRepository _loyalty = LoyaltyRepository(_db);
  late final GiftCardRepository _giftCards = GiftCardRepository(_db);
  late final QuoteRepository _quotes = QuoteRepository(_db);
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  final _lines = <_CartLine>[];
  // Escalones de mayoreo por producto, cacheados al entrar al carrito.
  final Map<int, List<PriceTier>> _tiersByProduct = {};
  int? _locationId;
  int _lowStock = 0;
  Customer? _customer; // cliente opcional asignado a la venta
  int? _originQuoteId; // cotización de origen si el carrito se cargó de una

  // Vitrina
  List<Category> _categories = [];
  List<Product> _products = [];
  int? _categoryFilter; // null = todas

  // Ancho a partir del cual mostramos los dos paneles (tablet horizontal).
  static const _wideBreakpoint = 720.0;

  // El escaneo por cámara solo aplica en móvil; en PC se usa lector USB.
  static bool get _cameraCapable =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

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
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    final cats = await _catalog.categories();
    final prods = await _catalog.productsByCategory(_categoryFilter);
    if (mounted) {
      setState(() {
        _categories = cats;
        _products = prods;
      });
    }
  }

  /// Recarga la vitrina sin perder el carrito. La llama el shell al volver a la
  /// pestaña Vender (p. ej. tras cargar el catálogo de prueba desde Admin).
  void reloadCatalog() {
    _loadCatalog();
    _refreshLowStock();
  }

  Future<void> _selectCategory(int? id) async {
    setState(() => _categoryFilter = id);
    final prods = await _catalog.productsByCategory(id);
    if (mounted) setState(() => _products = prods);
  }

  Future<void> _refreshLowStock() async {
    final n = await _inventory.lowStockCount();
    if (mounted) setState(() => _lowStock = n);
  }

  Future<void> _openInventory(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    _refreshLowStock();
    _loadCatalog();
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
      _reprice();
    });
    _ensureTiers(product.id);
  }

  /// Carga (una vez) los escalones de mayoreo de un producto y recalcula. Si el
  /// producto no tiene escalones, guarda una lista vacía para no reconsultar.
  Future<void> _ensureTiers(int productId) async {
    if (_tiersByProduct.containsKey(productId)) return;
    final tiers = await _catalog.priceTiersOf(productId);
    if (!mounted) return;
    setState(() {
      _tiersByProduct[productId] = tiers;
      _reprice();
    });
  }

  /// Recalcula el precio unitario de cada línea según el mayoreo. La cantidad
  /// se cuenta **surtida** por producto (todas las variantes del mismo modelo
  /// suman hacia el umbral), así 6 negras + 6 blancas activan el mayoreo de 10.
  void _reprice() {
    final qtyByProduct = <int, int>{};
    for (final l in _lines) {
      qtyByProduct[l.product.id] = (qtyByProduct[l.product.id] ?? 0) + l.qty;
    }
    for (final l in _lines) {
      final tiers = _tiersByProduct[l.product.id];
      final wholesale = (tiers == null || tiers.isEmpty)
          ? null
          : wholesalePriceFor(tiers, qtyByProduct[l.product.id]!);
      l.unitPriceCents = wholesale ?? l.retailUnitPriceCents;
      l.wholesaleApplied = wholesale != null;
    }
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

  Future<void> _scanWithCamera() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null) await _onScan(code);
  }

  Future<void> _pickCustomer() async {
    final c = await pickCustomer(context, _customers);
    if (c != null && mounted) setState(() => _customer = c);
  }

  Future<void> _openSearch() async {
    final picked = await pickProductAndVariant(context, _catalog);
    if (picked != null) _addVariant(picked.$1, picked.$2);
    _scanFocus.requestFocus();
  }

  /// Al tocar un producto de la vitrina: elegir talla/color y agregar.
  Future<void> _onTapProduct(Product product) async {
    final variant = await pickVariant(context, _catalog, product);
    if (variant != null) _addVariant(product, variant);
  }

  void _changeQty(_CartLine line, int delta) {
    setState(() {
      line.qty += delta;
      if (line.qty <= 0) _lines.remove(line);
      _reprice();
    });
  }

  // -------------------------------------------------------------------------
  // Cotizaciones
  // -------------------------------------------------------------------------

  /// Guarda el carrito actual como cotización (no cobra, no toca inventario).
  Future<void> _saveQuote() async {
    if (_lines.isEmpty) return;
    final opts = await showModalBottomSheet<_QuoteOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuoteOptionsSheet(customer: _customer),
    );
    if (opts == null) return;
    try {
      final draft = [
        for (final l in _lines)
          QuoteDraftLine(
            variantId: l.variant.id,
            qty: l.qty,
            unitPriceCents: l.unitPriceCents,
            lineDiscountCents: l.lineDiscountCents,
          ),
      ];
      final q = await _quotes.create(
        actor: _cashier,
        lines: draft,
        customerId: _customer?.id,
        notes: opts.notes,
        validDays: opts.validDays,
      );
      if (!mounted) return;
      _toast('Cotización ${q.folio} guardada');
      setState(() {
        _lines.clear();
        _customer = null;
        _originQuoteId = null;
      });
      _scanFocus.requestFocus();
    } catch (e) {
      _toast('No se pudo guardar la cotización: $e');
    }
  }

  /// Abre la lista de cotizaciones; si se elige una para "pasar a venta", la
  /// carga al carrito.
  Future<void> _openQuotes() async {
    final q = await Navigator.of(context)
        .push<Quote>(MaterialPageRoute(builder: (_) => const QuotesScreen()));
    if (q != null) await _loadQuote(q);
    _scanFocus.requestFocus();
  }

  /// Carga los renglones de una cotización al carrito (respetando su precio) y
  /// recuerda su origen para marcarla convertida al cobrar.
  Future<void> _loadQuote(Quote q) async {
    final lines = await _quotes.linesOf(q.id);
    final loaded = <_CartLine>[];
    for (final l in lines) {
      final v = await _catalog.variantById(l.variantId);
      if (v == null) continue;
      final p = await _catalog.productOfVariant(v);
      if (p == null) continue;
      final cl = _CartLine(p, v, l.unitPriceCents, l.qty);
      cl.lineDiscountCents = l.lineDiscountCents;
      loaded.add(cl);
    }
    Customer? cust;
    if (q.customerId != null) cust = await _customers.byId(q.customerId!);
    if (!mounted) return;
    setState(() {
      _lines
        ..clear()
        ..addAll(loaded);
      _customer = cust;
      _originQuoteId = q.id;
      _reprice();
    });
    _toast('Cotización ${q.folio} cargada al carrito');
  }

  Future<void> _checkout() async {
    if (_lines.isEmpty || _locationId == null) return;
    final payment = await showModalBottomSheet<_PaymentResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(
        grossCents: _total,
        customers: _customers,
        loyalty: _loyalty,
        giftCards: _giftCards,
        initialCustomer: _customer,
      ),
    );
    if (payment == null) return;
    // El cliente pudo elegirse/cambiarse dentro del cobro.
    if (mounted) setState(() => _customer = payment.customer);

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
        customerId: _customer?.id,
        redeemPoints: payment.redeemPoints,
      );
    } catch (e) {
      _toast('Error al cobrar: $e');
      return;
    }

    // Si el carrito venía de una cotización, márcala convertida.
    if (_originQuoteId != null) {
      await _quotes.markConverted(_originQuoteId!, result.saleId);
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

    final ticketCfg = await TicketConfig.load(_db);

    var printed = true;
    try {
      await Printing.layoutPdf(
        onLayout: (_) => TicketService.buildPdf(ticket, config: ticketCfg),
        name: 'ticket_${result.folio}',
      );
    } catch (_) {
      printed = false;
    }

    if (!mounted) return;
    await _showDone(result, printed);
    setState(() {
      _lines.clear();
      _customer = null;
      _originQuoteId = null;
    });
    _refreshLowStock();
    _loadCatalog();
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
            if (r.redeemedPoints > 0 || r.earnedPoints > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  [
                    if (r.redeemedPoints > 0) 'Canjeó ${r.redeemedPoints} pts',
                    if (r.earnedPoints > 0) 'Ganó ${r.earnedPoints} pts',
                  ].join('  ·  '),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
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

  // -------------------------------------------------------------------------
  // Layout responsivo
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onMenu,
                tooltip: 'Menú'),
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
            onPressed: _pickCustomer,
            icon: Icon(
                _customer == null ? Icons.person_add_alt : Icons.person),
            tooltip: _customer == null
                ? 'Asignar cliente'
                : 'Cliente: ${_customer!.name}',
          ),
          IconButton(
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
            tooltip: 'Buscar producto',
          ),
          if (!narrow) ...[
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
                MaterialPageRoute(builder: (_) => const GiftCardsScreen()),
              ),
              icon: const Icon(Icons.card_giftcard),
              tooltip: 'Tarjetas de regalo',
            ),
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReturnsScreen()),
              ),
              icon: const Icon(Icons.assignment_return_outlined),
              tooltip: 'Devoluciones y cambios',
            ),
            IconButton(
              onPressed: _openQuotes,
              icon: const Icon(Icons.request_quote_outlined),
              tooltip: 'Cotizaciones',
            ),
          ] else
            PopupMenuButton<String>(
              tooltip: 'Más',
              onSelected: (v) {
                switch (v) {
                  case 'inv':
                    _openInventory(const InventoryHomeScreen());
                  case 'lay':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const LayawaysScreen()));
                  case 'gift':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const GiftCardsScreen()));
                  case 'ret':
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ReturnsScreen()));
                  case 'quote':
                    _openQuotes();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'inv',
                    child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('Inventario'))),
                PopupMenuItem(
                    value: 'lay',
                    child: ListTile(
                        leading: Icon(Icons.bookmark_border),
                        title: Text('Apartados'))),
                PopupMenuItem(
                    value: 'gift',
                    child: ListTile(
                        leading: Icon(Icons.card_giftcard),
                        title: Text('Tarjetas de regalo'))),
                PopupMenuItem(
                    value: 'ret',
                    child: ListTile(
                        leading: Icon(Icons.assignment_return_outlined),
                        title: Text('Devoluciones y cambios'))),
                PopupMenuItem(
                    value: 'quote',
                    child: ListTile(
                        leading: Icon(Icons.request_quote_outlined),
                        title: Text('Cotizaciones'))),
              ],
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          return wide ? _wideLayout() : _narrowLayout();
        },
      ),
    );
  }

  /// Tablet: dos paneles (carrito 40% + vitrina 60%).
  Widget _wideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: Material(
            elevation: 2,
            child: Column(
              children: [
                _cartHeader(),
                Expanded(child: _cartList()),
                _summaryBar(showCheckout: true),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(flex: 3, child: _catalogPanel(autofocusScan: true)),
      ],
    );
  }

  /// Celular / vertical: vitrina full + barra de carrito inferior.
  Widget _narrowLayout() {
    return Column(
      children: [
        Expanded(child: _catalogPanel(autofocusScan: false)),
        _mobileCartBar(),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Vitrina (catálogo)
  // -------------------------------------------------------------------------
  Widget _catalogPanel({required bool autofocusScan}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _scanCtrl,
                  focusNode: _scanFocus,
                  autofocus: autofocusScan,
                  decoration: const InputDecoration(
                    labelText: 'Escanea o busca (+ Enter)',
                    prefixIcon: Icon(Icons.qr_code_scanner),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: _onScan,
                ),
              ),
              // En PC el escaneo es por lector USB (teclea al campo): la cámara
              // solo aplica en móvil.
              if (_cameraCapable) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _scanWithCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Cámara'),
                ),
              ],
            ],
          ),
        ),
        if (_customer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(Icons.person, size: 18),
                label: Text(_customer!.name),
                onDeleted: () => setState(() => _customer = null),
              ),
            ),
          ),
        _categoryTabs(),
        Expanded(child: _productGrid()),
      ],
    );
  }

  Widget _categoryTabs() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Todo'),
              selected: _categoryFilter == null,
              onSelected: (_) => _selectCategory(null),
            ),
          ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.name),
                selected: _categoryFilter == c.id,
                onSelected: (_) => _selectCategory(c.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _productGrid() {
    if (_products.isEmpty) {
      return const Center(child: Text('Sin productos en esta categoría'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 190,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _products.length,
      itemBuilder: (_, i) => _ProductTile(
        product: _products[i],
        onTap: () => _onTapProduct(_products[i]),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Carrito
  // -------------------------------------------------------------------------
  Widget _cartHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Carrito', style: Theme.of(context).textTheme.titleMedium),
          Text('$_itemCount artículos',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _cartList() {
    if (_lines.isEmpty) {
      return const Center(child: Text('Carrito vacío'));
    }
    return ListView.separated(
      itemCount: _lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _cartTile(_lines[i]),
    );
  }

  Widget _cartTile(_CartLine line) {
    final unit = '\$${(line.unitPriceCents / 100).toStringAsFixed(2)}';
    final subtitle = line.lineDiscountCents > 0
        ? '$unit c/u  ·  −\$${(line.lineDiscountCents / 100).toStringAsFixed(2)}  ·  = \$${(line.net / 100).toStringAsFixed(2)}'
        : '$unit c/u  ·  = \$${(line.lineTotal / 100).toStringAsFixed(2)}';
    return ListTile(
      dense: true,
      title: Row(
        children: [
          Expanded(child: Text(line.title)),
          if (line.wholesaleApplied) _mayoreoBadge(),
        ],
      ),
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

  /// Distintivo "Mayoreo" para las líneas cuyo precio cayó a un escalón.
  Widget _mayoreoBadge() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 14, color: scheme.onPrimaryContainer),
          const SizedBox(width: 2),
          Text('Mayoreo',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer)),
        ],
      ),
    );
  }

  /// Barra inferior del celular: contador, total y abrir carrito / cobrar.
  Widget _mobileCartBar() {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: _lines.isEmpty ? null : _openCartSheet,
              icon: Badge(
                isLabelVisible: _itemCount > 0,
                label: Text('$_itemCount'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Total', style: theme.textTheme.bodySmall),
                  Text('\$${(_total / 100).toStringAsFixed(2)}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _lines.isEmpty ? null : _checkout,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Cobrar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Hoja inferior con el carrito editable (celular).
  void _openCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          // Reconstruye la hoja cuando cambian cantidades desde ella.
          void refresh() {
            setSheet(() {});
            setState(() {});
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (_, controller) => Column(
              children: [
                _cartHeader(),
                Expanded(
                  child: _lines.isEmpty
                      ? const Center(child: Text('Carrito vacío'))
                      : ListView.separated(
                          controller: controller,
                          itemCount: _lines.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final line = _lines[i];
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Expanded(child: Text(line.title)),
                                  if (line.wholesaleApplied) _mayoreoBadge(),
                                ],
                              ),
                              subtitle: Text(
                                  '\$${(line.unitPriceCents / 100).toStringAsFixed(2)} c/u  ·  = \$${(line.net / 100).toStringAsFixed(2)}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      tooltip: 'Descuento',
                                      onPressed: () async {
                                        await _editLineDiscount(line);
                                        refresh();
                                      },
                                      icon: Icon(Icons.local_offer_outlined,
                                          color: line.lineDiscountCents > 0
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                              : null)),
                                  IconButton(
                                      onPressed: () {
                                        _changeQty(line, -1);
                                        refresh();
                                      },
                                      icon: const Icon(
                                          Icons.remove_circle_outline)),
                                  Text('${line.qty}',
                                      style: const TextStyle(fontSize: 18)),
                                  IconButton(
                                      onPressed: () {
                                        _changeQty(line, 1);
                                        refresh();
                                      },
                                      icon:
                                          const Icon(Icons.add_circle_outline)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total: \$${(_total / 100).toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleLarge),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _lines.isEmpty
                                ? null
                                : () {
                                    Navigator.of(sheetCtx).pop();
                                    _saveQuote();
                                  },
                            icon: const Icon(Icons.request_quote_outlined),
                            label: const Text('Cotizar'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _lines.isEmpty
                                ? null
                                : () {
                                    Navigator.of(sheetCtx).pop();
                                    _checkout();
                                  },
                            icon: const Icon(Icons.point_of_sale),
                            label: const Text('Cobrar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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

  Widget _summaryBar({required bool showCheckout}) {
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
            if (showCheckout) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _lines.isEmpty ? null : _saveQuote,
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Cotización'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _lines.isEmpty ? null : _checkout,
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text('Cobrar'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mosaico de producto de la vitrina: foto (o marcador), nombre y precio.
class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = productImageProvider(product.imagePath);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: provider != null
                  ? Image(
                      // Miniatura en memoria (ResizeImage): no descomprime la
                      // foto completa para pintar un mosaico chico.
                      image: ResizeImage(provider, width: 320, allowUpscaling: false),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(theme),
                    )
                  : _placeholder(theme),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500)),
                  Text('\$${(product.basePriceCents / 100).toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.checkroom,
            size: 40, color: theme.colorScheme.onSurfaceVariant),
      );
}

// ===========================================================================
// Cobro: pago dividido, descuento y ticket de regalo
// ===========================================================================

String _methodLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => 'Efectivo',
      PaymentMethod.card => 'Tarjeta',
      PaymentMethod.transfer => 'Transferencia',
      PaymentMethod.creditNote => 'Nota de crédito',
      PaymentMethod.giftCard => 'Tarjeta de regalo',
    };

class _PaymentResult {
  const _PaymentResult({
    required this.payments,
    required this.discountCents,
    required this.discountReason,
    required this.gift,
    required this.redeemPoints,
    required this.customer,
  });
  final List<PaymentInput> payments;
  final int discountCents;
  final String? discountReason;
  final bool gift;
  final int redeemPoints; // puntos de lealtad a canjear
  final Customer? customer; // cliente elegido en el cobro
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.grossCents,
    required this.customers,
    required this.loyalty,
    required this.giftCards,
    this.initialCustomer,
  });
  final int grossCents;
  final CustomerRepository customers;
  final LoyaltyRepository loyalty;
  final GiftCardRepository giftCards;
  final Customer? initialCustomer;

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

  // Lealtad / cliente (se puede elegir aquí mismo).
  Customer? _customer;
  int _availablePoints = 0;
  int _redeemCentsPerPoint = LoyaltyRepository.defaultRedeemCentsPerPoint;
  int _redeemPoints = 0;

  // Pago con tarjeta de regalo.
  int? _giftCardId;
  String? _giftCardCode;
  int _giftCardCents = 0;

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer;
    if (_customer != null) _loadPoints();
  }

  Future<void> _loadPoints() async {
    final pts = await widget.loyalty.balance(_customer!.id);
    final cfg = await widget.loyalty.config();
    if (!mounted) return;
    setState(() {
      _availablePoints = pts;
      _redeemCentsPerPoint = cfg.redeemCentsPerPoint;
    });
  }

  Future<void> _changeCustomer() async {
    final c = await pickCustomer(context, widget.customers);
    if (c == null || !mounted) return;
    setState(() {
      _customer = c;
      _redeemPoints = 0;
      _availablePoints = 0;
    });
    await _loadPoints();
    _syncCash();
  }

  /// Puntos máximos canjeables: no más de los que tiene ni de lo que cubre el bruto.
  int get _maxRedeemPoints {
    final coverable =
        ((widget.grossCents - _rawDiscountCents) / _redeemCentsPerPoint).floor();
    final cap = coverable < 0 ? 0 : coverable;
    return _availablePoints < cap ? _availablePoints : cap;
  }

  int get _redeemValue => _redeemPoints * _redeemCentsPerPoint;

  void _setRedeem(int points) {
    setState(() => _redeemPoints = points.clamp(0, _maxRedeemPoints));
    _syncCash();
  }

  /// Ajusta el efectivo sugerido al neto tras descuento y canje.
  void _syncCash() {
    _cash.text = (_net / 100).toStringAsFixed(2);
    setState(() {});
  }

  int _cents(TextEditingController c) =>
      ((double.tryParse(c.text.trim()) ?? 0) * 100).round();

  int get _rawDiscountCents => _cents(_discount).clamp(0, widget.grossCents);
  int get _discountCents => _rawDiscountCents;
  int get _net =>
      (widget.grossCents - _discountCents - _redeemValue).clamp(0, widget.grossCents);
  int get _nonCash => _cents(_card) + _cents(_transfer) + _giftCardCents;

  /// Pide un código de tarjeta de regalo y aplica su saldo a lo que falta pagar.
  Future<void> _addGiftCard() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tarjeta de regalo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Código de la tarjeta'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final found = await widget.giftCards.findByCode(code);
    if (!mounted) return;
    if (found == null || found.balanceCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tarjeta no encontrada o sin saldo')));
      return;
    }
    // Aplica lo que falta cubrir sin efectivo, hasta el saldo de la tarjeta.
    final stillDue = _net - _cents(_card) - _cents(_transfer);
    final apply = found.balanceCents < stillDue ? found.balanceCents : stillDue;
    setState(() {
      _giftCardId = found.card.id;
      _giftCardCode = found.card.code;
      _giftCardCents = apply < 0 ? 0 : apply;
    });
    _syncCash();
  }

  void _removeGiftCard() {
    setState(() {
      _giftCardId = null;
      _giftCardCode = null;
      _giftCardCents = 0;
    });
    _syncCash();
  }
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
      if (_giftCardCents > 0 && _giftCardId != null)
        PaymentInput(PaymentMethod.giftCard, _giftCardCents,
            giftCardId: _giftCardId),
    ];
    if (!mounted) return;
    Navigator.of(context).pop(_PaymentResult(
      payments: payments,
      discountCents: _discountCents,
      discountReason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      gift: _gift,
      redeemPoints: _redeemPoints,
      customer: _customer,
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
            // Cliente (opcional): se puede elegir o cambiar aquí en el cobro.
            InkWell(
              onTap: _changeCustomer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(_customer == null
                        ? Icons.person_add_alt
                        : Icons.person),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _customer?.name ?? 'Agregar cliente (opcional)',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(_customer == null ? 'Elegir' : 'Cambiar',
                        style: TextStyle(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            ),
            const Divider(height: 8),
            const SizedBox(height: 8),
            Text('A cobrar: \$${(_net / 100).toStringAsFixed(2)}',
                style: theme.textTheme.titleLarge),
            if (_discountCents > 0 || _redeemValue > 0)
              Text(
                  'Bruto \$${(widget.grossCents / 100).toStringAsFixed(2)}'
                  '${_discountCents > 0 ? '  ·  descuento \$${(_discountCents / 100).toStringAsFixed(2)}' : ''}'
                  '${_redeemValue > 0 ? '  ·  puntos -\$${(_redeemValue / 100).toStringAsFixed(2)}' : ''}'
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
            if (_availablePoints > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _redeemPoints > 0
                          ? 'Canjeando $_redeemPoints pts de $_availablePoints'
                          : 'Puntos disponibles: $_availablePoints',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (_redeemPoints > 0)
                    TextButton(
                        onPressed: () => _setRedeem(0),
                        child: const Text('Quitar')),
                  FilledButton.tonal(
                    onPressed:
                        _maxRedeemPoints == 0 ? null : () => _setRedeem(_maxRedeemPoints),
                    child: const Text('Canjear máx'),
                  ),
                ],
              ),
            ],
            const Divider(height: 24),
            _amountField('Efectivo', _cash),
            const SizedBox(height: 8),
            _amountField('Tarjeta', _card),
            const SizedBox(height: 8),
            _amountField('Transferencia', _transfer),
            const SizedBox(height: 8),
            _giftCardCents > 0
                ? Row(
                    children: [
                      const Icon(Icons.card_giftcard, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Tarjeta ${_giftCardCode ?? ''}: -\$${(_giftCardCents / 100).toStringAsFixed(2)}'),
                      ),
                      TextButton(
                          onPressed: _removeGiftCard,
                          child: const Text('Quitar')),
                    ],
                  )
                : OutlinedButton.icon(
                    onPressed: _addGiftCard,
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    label: const Text('Pagar con tarjeta de regalo'),
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

// ===========================================================================
// Guardar cotización: vigencia y nota
// ===========================================================================

class _QuoteOptions {
  const _QuoteOptions(this.validDays, this.notes);
  final int? validDays; // null = sin vencimiento
  final String? notes;
}

class _QuoteOptionsSheet extends StatefulWidget {
  const _QuoteOptionsSheet({this.customer});
  final Customer? customer;

  @override
  State<_QuoteOptionsSheet> createState() => _QuoteOptionsSheetState();
}

class _QuoteOptionsSheetState extends State<_QuoteOptionsSheet> {
  // null = sin vencimiento; de lo contrario, días de vigencia.
  int? _validDays = 15;
  final _notes = TextEditingController();

  static const _options = <(int?, String)>[
    (7, '7 días'),
    (15, '15 días'),
    (30, '30 días'),
    (null, 'Sin vencimiento'),
  ];

  @override
  void dispose() {
    _notes.dispose();
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
          Text('Guardar cotización', style: theme.textTheme.titleLarge),
          if (widget.customer != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Cliente: ${widget.customer!.name}',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 12),
          Text('Vigencia', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final (days, label) in _options)
                ChoiceChip(
                  label: Text(label),
                  selected: _validDays == days,
                  onSelected: (_) => setState(() => _validDays = days),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(_QuoteOptions(
              _validDays,
              _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            )),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar cotización'),
          ),
        ],
      ),
    );
  }
}
