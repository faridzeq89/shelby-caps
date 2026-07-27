import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';

/// Flujo tipo e-commerce: elegir prenda → elegir variante (talla/color con las
/// combinaciones sin existencia desactivadas). Devuelve la variante elegida.
Future<(Product, Variant)?> pickProductAndVariant(
    BuildContext context, CatalogRepository catalog) async {
  final product = await showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ProductSearchSheet(catalog: catalog),
  );
  if (product == null || !context.mounted) return null;
  final variant = await showModalBottomSheet<Variant>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VariantPickerSheet(catalog: catalog, product: product),
  );
  if (variant == null) return null;
  return (product, variant);
}

/// Selector de variante para un producto YA elegido (p. ej. al tocar su mosaico
/// en la vitrina). Devuelve la variante talla/color escogida, o null.
Future<Variant?> pickVariant(
    BuildContext context, CatalogRepository catalog, Product product) {
  return showModalBottomSheet<Variant>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _VariantPickerSheet(catalog: catalog, product: product),
  );
}

class _ProductSearchSheet extends StatefulWidget {
  const _ProductSearchSheet({required this.catalog});
  final CatalogRepository catalog;

  @override
  State<_ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends State<_ProductSearchSheet> {
  List<Product> _results = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final r = await widget.catalog.searchProducts(q);
      if (mounted) setState(() => _results = r);
    });
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
                labelText: 'Buscar prenda (nombre o SKU)',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final p = _results[i];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: p.brand != null ? Text(p.brand!) : null,
                    trailing: Text(
                        '\$${(p.basePriceCents / 100).toStringAsFixed(2)}'),
                    onTap: () => Navigator.of(context).pop(p),
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

class _VariantPickerSheet extends StatefulWidget {
  const _VariantPickerSheet({required this.catalog, required this.product});
  final CatalogRepository catalog;
  final Product product;

  @override
  State<_VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<_VariantPickerSheet> {
  List<(Variant, int)>? _variants;
  final _byKey = <String, (Variant, int)>{};
  List<String> _sizes = [];
  List<String> _colors = [];
  String? _size;
  String? _color;

  @override
  void initState() {
    super.initState();
    widget.catalog.variantsWithStock(widget.product.id).then((v) {
      if (!mounted) return;
      setState(() {
        _variants = v;
        for (final e in v) {
          _byKey['${e.$1.size ?? ''}|${e.$1.color ?? ''}'] = e;
        }
        _sizes = v.map((e) => e.$1.size).whereType<String>().toSet().toList();
        _colors = v.map((e) => e.$1.color).whereType<String>().toSet().toList();
      });
    });
  }

  int _availFor(String? size, String? color) =>
      _byKey['${size ?? ''}|${color ?? ''}']?.$2 ?? 0;

  bool _sizeEnabled(String size) {
    if (_colors.isEmpty) return _availFor(size, null) > 0;
    if (_color != null) return _availFor(size, _color) > 0;
    return _colors.any((c) => _availFor(size, c) > 0);
  }

  bool _colorEnabled(String color) {
    if (_sizes.isEmpty) return _availFor(null, color) > 0;
    if (_size != null) return _availFor(_size, color) > 0;
    return _sizes.any((s) => _availFor(s, color) > 0);
  }

  (Variant, int)? get _current {
    final needSize = _sizes.isNotEmpty;
    final needColor = _colors.isNotEmpty;
    if (needSize && _size == null) return null;
    if (needColor && _color == null) return null;
    return _byKey['${needSize ? _size : ''}|${needColor ? _color : ''}'];
  }

  int get _totalAvailable => (_variants ?? []).fold<int>(0, (s, e) => s + e.$2);

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
      child: _variants == null
          ? const SizedBox(
              height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.product.name, style: theme.textTheme.titleLarge),
                  Text(
                      'Precio \$${(widget.product.basePriceCents / 100).toStringAsFixed(2)}  ·  '
                      'Stock total: $_totalAvailable',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  if (_sizes.isNotEmpty) ...[
                    const Text('Talla'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final s in _sizes)
                          ChoiceChip(
                            label: Text(s),
                            selected: _size == s,
                            onSelected: _sizeEnabled(s)
                                ? (on) => setState(() {
                                      _size = on ? s : null;
                                      if (_color != null &&
                                          _availFor(_size, _color) <= 0) {
                                        _color = null;
                                      }
                                    })
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_colors.isNotEmpty) ...[
                    const Text('Color'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final c in _colors)
                          ChoiceChip(
                            label: Text(c),
                            selected: _color == c,
                            onSelected: _colorEnabled(c)
                                ? (on) => setState(() {
                                      _color = on ? c : null;
                                      if (_size != null &&
                                          _availFor(_size, _color) <= 0) {
                                        _size = null;
                                      }
                                    })
                                : null,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_current != null)
                    Text('Disponible: ${_current!.$2}',
                        style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_current != null && _current!.$2 > 0)
                          ? () => Navigator.of(context).pop(_current!.$1)
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Elegir'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
