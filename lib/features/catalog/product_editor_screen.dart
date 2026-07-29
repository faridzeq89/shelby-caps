import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/image_service.dart';
import 'label_service.dart';

class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _VariantRow {
  _VariantRow(this.variant, this.stock, this.barcodes);
  final Variant variant;
  final VariantStockData stock;
  final List<Barcode> barcodes;

  String? get internalCode => barcodes
      .cast<Barcode?>()
      .firstWhere((b) => b?.source == BarcodeSource.internal, orElse: () => null)
      ?.code;
}

class _EditorData {
  _EditorData(this.product, this.rows);
  final Product product;
  final List<_VariantRow> rows;
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _repo = CatalogRepository(_db);
  final ImageService _images = ImageService();
  late Future<_EditorData> _future = _load();
  int? _locationId;
  String? _scanResult;

  Profile get _actor => context.read<AuthController>().currentUser!;
  bool get _canSeeCosts => Permissions.canSeeCosts(_actor.role);

  Future<_EditorData> _load() async {
    _locationId ??= (await _db.select(_db.locations).getSingleOrNull())?.id;
    final product = await _repo.productById(widget.productId);
    final variants = await _repo.variantsOf(widget.productId);
    final rows = <_VariantRow>[];
    for (final v in variants) {
      rows.add(_VariantRow(
        v,
        await _db.stockFor(v.id),
        await _repo.barcodesOf(v.id),
      ));
    }
    return _EditorData(product!, rows);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  // --------------------------------------------------------------------------
  Future<void> _generateVariants() async {
    final result = await showDialog<_MatrixResult>(
      context: context,
      builder: (_) => const _MatrixDialog(),
    );
    if (result == null) return;
    try {
      final created = await _repo.generateVariantMatrix(
        _actor,
        productId: widget.productId,
        sizes: result.sizes,
        colors: result.colors,
        costCents: result.costCents,
        initialStock: result.initialStock,
        locationId: _locationId,
      );
      _toast('${created.length} variantes creadas');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _printLabels(_EditorData data) async {
    final labels = <LabelData>[];
    for (final r in data.rows) {
      final code = r.internalCode;
      if (code == null) continue;
      labels.add(LabelData(
        productName: data.product.name,
        code: code,
        priceCents: effectivePrice(data.product, r.variant),
        size: r.variant.size,
        color: r.variant.color,
      ));
    }
    if (labels.isEmpty) {
      _toast('No hay variantes con código para imprimir');
      return;
    }
    await Printing.layoutPdf(
      onLayout: (_) => LabelService.buildSheetPdf(labels),
      name: 'etiquetas_${data.product.name}',
    );
  }

  void _showZpl(_EditorData data) {
    final labels = [
      for (final r in data.rows)
        if (r.internalCode != null)
          LabelData(
            productName: data.product.name,
            code: r.internalCode!,
            priceCents: effectivePrice(data.product, r.variant),
            size: r.variant.size,
            color: r.variant.color,
          ),
    ];
    final zpl = LabelService.buildZpl(labels);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ZPL para etiquetadora Zebra'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(zpl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: zpl));
              Navigator.of(context).pop();
              _toast('ZPL copiado');
            },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _testScan(String code) async {
    if (code.trim().isEmpty) return;
    final v = await _repo.resolveByCode(code);
    setState(() {
      _scanResult = v == null
          ? 'Código "$code": sin resultado'
          : 'Código "$code" → ${v.sku}  (${v.size ?? ''} ${v.color ?? ''})';
    });
  }

  Future<void> _editPrice(_EditorData data, {Variant? variant}) async {
    final current = variant != null
        ? effectivePrice(data.product, variant)
        : data.product.basePriceCents;
    final cents = await _askPesos(
        variant == null ? 'Precio base del producto' : 'Precio de la variante',
        current);
    if (cents == null) return;
    try {
      if (variant == null) {
        await _repo.updateProductBasePrice(
            actor: _actor, productId: data.product.id, newPriceCents: cents);
      } else {
        await _repo.updateVariantPrice(
            actor: _actor, variantId: variant.id, newPriceCents: cents);
      }
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _editCost(Variant variant) async {
    final cents = await _askPesos('Costo de la variante', variant.costCents);
    if (cents == null) return;
    try {
      await _repo.updateVariantCost(
          actor: _actor, variantId: variant.id, newCostCents: cents);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _addSupplierCode(Variant variant) async {
    final code = await _askText('Código de proveedor (escanea o teclea)');
    if (code == null || code.trim().isEmpty) return;
    try {
      await _repo.addSupplierBarcode(_actor, variant.id, code.trim());
      _toast('Código vinculado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  // --------------------------------------------------------------------------
  // Archivar / borrar producto
  // --------------------------------------------------------------------------
  Future<void> _toggleArchive(_EditorData data) async {
    final activate = !data.product.active;
    try {
      await _repo.setProductActive(_actor, data.product.id, activate);
      _toast(activate ? 'Producto reactivado' : 'Producto archivado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _delete(_EditorData data) async {
    final canDelete = await _repo.canDeleteProduct(data.product.id);
    if (!mounted) return;
    if (!canDelete) {
      // Tiene historial → no se puede borrar (ledger inmutable). Ofrecer archivar.
      final archive = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No se puede borrar'),
          content: const Text(
              'Este producto ya tiene ventas o movimientos de inventario, y el '
              'historial es inmutable. Puedes ARCHIVARLO: desaparece de la venta '
              'y la búsqueda pero conserva su historial. ¿Archivar?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Archivar')),
          ],
        ),
      );
      if (archive == true) await _toggleArchiveTo(data, false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
            '¿Borrar "${data.product.name}" de forma permanente? No tiene ventas '
            'ni movimientos, así que se puede eliminar por completo. Esta acción '
            'no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteProduct(_actor, data.product.id);
      if (!mounted) return;
      _toast('Producto eliminado');
      Navigator.of(context).pop(true);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _toggleArchiveTo(_EditorData data, bool active) async {
    try {
      await _repo.setProductActive(_actor, data.product.id, active);
      _toast(active ? 'Producto reactivado' : 'Producto archivado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  // --------------------------------------------------------------------------
  // Foto del producto
  // --------------------------------------------------------------------------
  Future<void> _changePhoto(_EditorData data) async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, _PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, _PhotoAction.gallery),
            ),
            if (data.product.imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Quitar foto'),
                onTap: () => Navigator.pop(context, _PhotoAction.remove),
              ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _PhotoAction.camera:
        await _pickImage(ImageSource.camera, data);
      case _PhotoAction.gallery:
        await _pickImage(ImageSource.gallery, data);
      case _PhotoAction.remove:
        await _setPhoto(data, null);
    }
  }

  Future<void> _pickImage(ImageSource source, _EditorData data) async {
    XFile? file;
    try {
      file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 92);
    } catch (e) {
      _toast('No se pudo abrir la cámara/galería: $e');
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final path = await _images.saveOptimizedBytes(bytes);
    if (path == null) {
      _toast('La imagen no es válida');
      return;
    }
    await _setPhoto(data, path);
  }

  /// Persiste la nueva ruta (o la quita con null) y borra el archivo anterior.
  Future<void> _setPhoto(_EditorData data, String? path) async {
    final old = data.product.imagePath;
    try {
      await _repo.updateProductImage(
          actor: _actor, productId: data.product.id, path: path);
      await _images.delete(old);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Widget _photoThumb(_EditorData data) {
    final provider = productImageProvider(data.product.imagePath);
    return InkWell(
      onTap: () => _changePhoto(data),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          image: provider != null
              ? DecorationImage(
                  image: ResizeImage(provider, width: 200, allowUpscaling: false),
                  fit: BoxFit.cover)
              : null,
        ),
        child: provider == null
            ? const Icon(Icons.add_a_photo_outlined)
            : null,
      ),
    );
  }

  Future<int?> _askPesos(String title, int initialCents) async {
    final ctrl =
        TextEditingController(text: (initialCents / 100).toStringAsFixed(2));
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return null;
    final value = double.tryParse(ctrl.text.trim());
    if (value == null || value < 0) return null;
    return (value * 100).round();
  }

  Future<String?> _askText(String title) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aceptar')),
        ],
      ),
    );
    return ok == true ? ctrl.text : null;
  }

  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EditorData>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final data = snap.data!;
        return Scaffold(
          appBar: AppBar(
            title: Text(data.product.name),
            actions: [
              IconButton(
                tooltip: 'Imprimir etiquetas (PDF)',
                icon: const Icon(Icons.print_outlined),
                onPressed: () => _printLabels(data),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'zpl':
                      _showZpl(data);
                    case 'archive':
                      _toggleArchive(data);
                    case 'delete':
                      _delete(data);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'zpl', child: Text('Ver ZPL (Zebra)')),
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(data.product.active
                        ? 'Archivar producto'
                        : 'Reactivar producto'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Eliminar producto'),
                  ),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _generateVariants,
            icon: const Icon(Icons.grid_on),
            label: const Text('Generar variantes'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              _header(data),
              _scanTester(),
              const Divider(),
              if (data.rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Sin variantes. Usa "Generar variantes" para crear la '
                    'matriz talla × color.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...data.rows.map((r) => _variantTile(data, r)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(_EditorData data) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _photoThumb(data),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!data.product.active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Chip(
                        label: const Text('ARCHIVADO'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.orange.shade100,
                        labelStyle: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                  if (data.product.brand != null)
                    Text(data.product.brand!,
                        style: Theme.of(context).textTheme.bodySmall),
                  Text('Precio base: \$${(data.product.basePriceCents / 100).toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  Text('IVA: ${(data.product.taxRateBps / 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _editPrice(data),
              icon: const Icon(Icons.edit),
              label: const Text('Precio'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scanTester() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Probar escaneo (escanea o teclea un código + Enter)',
              prefixIcon: Icon(Icons.qr_code_scanner),
            ),
            onSubmitted: _testScan,
          ),
          if (_scanResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_scanResult!,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }

  Widget _variantTile(_EditorData data, _VariantRow r) {
    final price = effectivePrice(data.product, r.variant);
    final subtitle = StringBuffer('SKU ${r.variant.sku}');
    subtitle.write('  ·  stock ${r.stock.available}');
    if (r.internalCode != null) subtitle.write('  ·  ${r.internalCode}');
    if (_canSeeCosts) {
      subtitle.write('  ·  costo \$${(r.variant.costCents / 100).toStringAsFixed(2)}');
    }
    return ListTile(
      title: Text(
          '${r.variant.size ?? ''} ${r.variant.color ?? ''}  —  \$${(price / 100).toStringAsFixed(2)}'),
      subtitle: Text(subtitle.toString()),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'price':
              _editPrice(data, variant: r.variant);
            case 'cost':
              _editCost(r.variant);
            case 'supplier':
              _addSupplierCode(r.variant);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'price', child: Text('Editar precio')),
          if (_canSeeCosts)
            const PopupMenuItem(value: 'cost', child: Text('Editar costo')),
          const PopupMenuItem(
              value: 'supplier', child: Text('Agregar código proveedor')),
        ],
      ),
    );
  }
}

enum _PhotoAction { camera, gallery, remove }

// ===========================================================================
// Diálogo del generador de matriz
// ===========================================================================

class _MatrixResult {
  _MatrixResult(this.sizes, this.colors, this.costCents, this.initialStock);
  final List<String> sizes;
  final List<String> colors;
  final int costCents;
  final int initialStock;
}

class _MatrixDialog extends StatefulWidget {
  const _MatrixDialog();

  @override
  State<_MatrixDialog> createState() => _MatrixDialogState();
}

class _MatrixDialogState extends State<_MatrixDialog> {
  static const _presetSizes = ['CH', 'M', 'G', 'XG', '28', '30', '32', '34'];
  final _selectedSizes = <String>{};
  final _customSizes = TextEditingController();
  final _colors = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController(text: '0');

  @override
  void dispose() {
    _customSizes.dispose();
    _colors.dispose();
    _cost.dispose();
    _stock.dispose();
    super.dispose();
  }

  /// Tallas finales = chips elegidos + las que el usuario escriba (sin duplicar,
  /// conservando el orden: primero los presets marcados, luego las nuevas).
  List<String> _allSizes() {
    final custom = _customSizes.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);
    return <String>{..._selectedSizes, ...custom}.toList();
  }

  List<String> _parseColors() => _colors.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Generar variantes (talla × color)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tallas'),
            Wrap(
              spacing: 6,
              children: [
                for (final s in _presetSizes)
                  FilterChip(
                    label: Text(s),
                    selected: _selectedSizes.contains(s),
                    onSelected: (on) => setState(() {
                      on ? _selectedSizes.add(s) : _selectedSizes.remove(s);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customSizes,
              decoration: const InputDecoration(
                labelText: 'Otras tallas (separadas por coma)',
                hintText: 'XCH, XXG, 36, 38, Unitalla…',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _colors,
              decoration: const InputDecoration(
                labelText: 'Colores (separados por coma)',
                hintText: 'Blanco, Negro, Rosa',
              ),
            ),
            TextField(
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Costo', prefixText: '\$'),
            ),
            TextField(
              controller: _stock,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Stock inicial por variante'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final sizes = _allSizes();
            final colors = _parseColors();
            if (sizes.isEmpty || colors.isEmpty) return;
            Navigator.of(context).pop(_MatrixResult(
              sizes,
              colors,
              ((double.tryParse(_cost.text.trim()) ?? 0) * 100).round(),
              int.tryParse(_stock.text.trim()) ?? 0,
            ));
          },
          child: const Text('Generar'),
        ),
      ],
    );
  }
}
