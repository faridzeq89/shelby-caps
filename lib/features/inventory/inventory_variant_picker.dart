import 'package:flutter/material.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';

/// Selector de variante para operaciones de inventario. A diferencia del
/// selector de venta, aquí SÍ se pueden elegir variantes sin existencia (se
/// recibe o ajusta justo cuando el stock está en cero). Acepta escaneo (Enter
/// del lector HID) o búsqueda por nombre/SKU.
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
  List<(Product, Variant)> _results = [];
  String? _note;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final r = await widget.catalog.searchVariants(q, limit: 30);
    if (mounted) setState(() => _results = r);
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

  String _sub(Product p, Variant v) {
    final talla = v.size ?? '';
    final color = v.color ?? '';
    final tc = '$talla $color'.trim();
    return tc.isEmpty ? v.sku : '$tc  ·  ${v.sku}';
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
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Escanea o busca (nombre o SKU)',
                prefixIcon: Icon(Icons.qr_code_scanner),
              ),
              onChanged: _search,
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
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final (p, v) = _results[i];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text(_sub(p, v)),
                    onTap: () => Navigator.of(context).pop((p, v)),
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
