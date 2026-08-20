import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../scan/scanner_screen.dart';

/// Selector de variante para operaciones de inventario. A diferencia del
/// selector de venta, aquí SÍ se pueden elegir variantes sin existencia (se
/// recibe o ajusta justo cuando el stock está en cero).
///
/// Muestra por defecto la lista de productos (sin necesidad de teclear), con
/// **filtros por categoría**, además de búsqueda por nombre/SKU y escaneo
/// (cámara o lector HID). Al tocar un producto se elige su variante.
Future<(Product, Variant)?> pickInventoryVariant(
    BuildContext context, CatalogRepository catalog) {
  return showModalBottomSheet<(Product, Variant)>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _InventoryVariantSheet(catalog: catalog),
  );
}

class _InventoryVariantSheet extends StatefulWidget {
  const _InventoryVariantSheet({required this.catalog});
  final CatalogRepository catalog;

  @override
  State<_InventoryVariantSheet> createState() => _InventoryVariantSheetState();
}

class _InventoryVariantSheetState extends State<_InventoryVariantSheet> {
  final _ctrl = TextEditingController();
  List<Category> _categories = [];
  int? _categoryId; // null = todas
  List<Product> _products = [];
  bool _loading = true;
  String? _note;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final cats = await widget.catalog.categories(activeOnly: true);
    if (mounted) setState(() => _categories = cats);
    await _load();
  }

  /// Carga la lista según búsqueda (si hay ≥2 letras) o categoría seleccionada.
  Future<void> _load() async {
    setState(() => _loading = true);
    final q = _ctrl.text.trim();
    final List<Product> list;
    if (q.length >= 2) {
      list = await widget.catalog.searchProductsOrCategory(q);
    } else {
      list = await widget.catalog.productsByCategory(_categoryId);
    }
    if (mounted) {
      setState(() {
        _products = list;
        _loading = false;
      });
    }
  }

  Future<void> _scanCamera() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null) await _onSubmit(code);
  }

  Future<void> _onSubmit(String code) async {
    final variant = await widget.catalog.resolveByCode(code);
    if (variant == null) {
      if (mounted) setState(() => _note = 'Código "$code" sin resultado');
      return;
    }
    final product = await widget.catalog.productOfVariant(variant);
    if (product != null && mounted) {
      Navigator.of(context).pop((product, variant));
    }
  }

  String _variantLabel(Variant v) {
    final tc = '${v.size ?? ''} ${v.color ?? ''}'.trim();
    return tc.isEmpty ? v.sku : tc;
  }

  /// Al tocar un producto: si tiene una sola variante la devuelve directo; si
  /// tiene varias (talla×color), muestra un selector para elegirla.
  Future<void> _pickVariant(Product p) async {
    final variants = await widget.catalog.variantsWithStock(p.id);
    if (!mounted) return;
    if (variants.isEmpty) {
      setState(() => _note = '"${p.name}" no tiene variantes activas');
      return;
    }
    if (variants.length == 1) {
      Navigator.of(context).pop((p, variants.first.$1));
      return;
    }
    final chosen = await showModalBottomSheet<Variant>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(p.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (v, stock) in variants)
                    ListTile(
                      leading: const Icon(Icons.style_outlined),
                      title: Text(_variantLabel(v)),
                      subtitle: Text('${v.sku}  ·  existencia: $stock'),
                      onTap: () => Navigator.of(context).pop(v),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) Navigator.of(context).pop((p, chosen));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 12,
        right: 12,
        top: 12,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: false,
              decoration: InputDecoration(
                labelText: 'Escanea o busca (producto, SKU o categoría)',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: IconButton(
                  tooltip: 'Escanear con cámara',
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: _scanCamera,
                ),
              ),
              onChanged: (_) => _load(),
              onSubmitted: _onSubmit,
            ),
            if (_note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_note!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            // Filtros por categoría (solo si no hay una búsqueda activa).
            if (_ctrl.text.trim().length < 2 && _categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('Todas'),
                        selected: _categoryId == null,
                        onSelected: (_) {
                          setState(() => _categoryId = null);
                          _load();
                        },
                      ),
                    ),
                    for (final c in _categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c.name),
                          selected: _categoryId == c.id,
                          onSelected: (_) {
                            setState(() => _categoryId = c.id);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? const Center(
                          child: Text('Sin productos en esta categoría'))
                      : ListView.separated(
                          itemCount: _products.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _products[i];
                            return ListTile(
                              leading: const Icon(Icons.inventory_2_outlined),
                              title: Text(p.name),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _pickVariant(p),
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
