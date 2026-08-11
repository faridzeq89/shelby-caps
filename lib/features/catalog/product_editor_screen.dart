import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/supplier_repository.dart';
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
  _EditorData(
      this.product, this.rows, this.tiers, this.supplierName, this.gallery);
  final Product product;
  final List<_VariantRow> rows;
  final List<PriceTier> tiers; // escalones de mayoreo
  final String? supplierName; // proveedor ligado (nombre), si hay
  final List<ProductImage> gallery; // fotos extra (la principal va en product)
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogRepository _repo = CatalogRepository(_db);
  late final SupplierRepository _suppliers = SupplierRepository(_db);
  final ImageService _images = ImageService();
  late Future<_EditorData> _future = _load();
  int? _locationId;
  String? _scanResult;

  Profile get _actor => context.read<AuthController>().currentUser!;
  bool get _canSeeCosts => Permissions.canSeeCosts(_actor.role);
  bool get _canEditPrices => Permissions.canEditPrices(_actor.role);

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
    final tiers = await _repo.priceTiersOf(widget.productId);
    final supplierName = product!.supplierId == null
        ? null
        : (await _suppliers.byId(product.supplierId!))?.name;
    final gallery = await _repo.galleryOf(widget.productId);
    return _EditorData(product, rows, tiers, supplierName, gallery);
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

  /// Elige el proveedor del producto (o lo quita). -1 = sin proveedor.
  Future<void> _editSupplier(_EditorData data) async {
    final suppliers = await _suppliers.all();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              dense: true,
              title: Text('Proveedor del producto',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Sin proveedor'),
              selected: data.product.supplierId == null,
              onTap: () => Navigator.of(context).pop(-1),
            ),
            for (final s in suppliers)
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(s.name),
                subtitle: s.phone == null ? null : Text(s.phone!),
                selected: data.product.supplierId == s.id,
                onTap: () => Navigator.of(context).pop(s.id),
              ),
            if (suppliers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'No hay proveedores. Créalos en Admin → Proveedores.',
                    textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await _repo.updateProductSupplier(
        actor: _actor,
        productId: data.product.id,
        supplierId: chosen == -1 ? null : chosen,
      );
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
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

  // --------------------------------------------------------------------------
  // Galería: varias vistas de la misma gorra (frente, perfil, atrás, detalle).
  // La primera es la principal; es la que sale en el POS, el ticket y como
  // portada en la tienda web. Las demás solo se ven en la ficha del catálogo.
  // --------------------------------------------------------------------------
  Widget _photoStrip(_EditorData data) {
    final theme = Theme.of(context);
    final main = data.product.imagePath;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            'Fotos',
            action: Text(
              main == null
                  ? 'sin fotos'
                  : '${1 + data.gallery.length} · la 1ª es la portada',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (main != null)
                  _photoTile(
                    path: main,
                    label: 'Portada',
                    onTap: () => _changePhoto(data),
                  ),
                for (final img in data.gallery)
                  _photoTile(
                    path: img.path,
                    onTap: () => _galleryMenu(data, img),
                  ),
                _addPhotoTile(data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTile({
    required String path,
    required VoidCallback onTap,
    String? label,
  }) {
    final provider = productImageProvider(path);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Stack(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: Border.all(color: Theme.of(context).dividerColor),
                image: provider != null
                    ? DecorationImage(
                        image: ResizeImage(provider,
                            width: 260, allowUpscaling: false),
                        fit: BoxFit.cover)
                    : null,
              ),
            ),
            if (label != null)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.charcoal.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.charcoalInk,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _addPhotoTile(_EditorData data) {
    return InkWell(
      onTap: () => _addPhoto(data),
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.brassDeep),
            SizedBox(height: 4),
            Text('Agregar',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  /// Agrega una foto a la galería (o la vuelve portada si aún no hay ninguna).
  Future<void> _addPhoto(_EditorData data) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final path = await _capture(source);
    if (path == null) return;
    try {
      await _repo.addProductImage(
          actor: _actor, productId: data.product.id, path: path);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  /// Qué hacer con una foto de la galería: subirla a portada o quitarla.
  Future<void> _galleryMenu(_EditorData data, ProductImage img) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Hacer portada'),
              subtitle: const Text('Es la que se ve en el POS y en la tienda'),
              onTap: () => Navigator.pop(context, 'main'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Quitar foto'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    try {
      if (action == 'main') {
        await _repo.setMainImage(
            actor: _actor, productId: data.product.id, imageId: img.id);
      } else {
        final path =
            await _repo.removeGalleryImage(actor: _actor, imageId: img.id);
        await _images.delete(path);
      }
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  /// Toma/elige una foto y la guarda optimizada. Devuelve la ruta local.
  Future<String?> _capture(ImageSource source) async {
    XFile? file;
    try {
      file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 92);
    } catch (e) {
      _toast('No se pudo abrir la cámara/galería: $e');
      return null;
    }
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final path = await _images.saveOptimizedBytes(bytes);
    if (path == null) _toast('La imagen no es válida');
    return path;
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
              _photoStrip(data),
              _mayoreoCard(data),
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
                  InkWell(
                    onTap: _canEditPrices ? () => _editSupplier(data) : null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Icon(Icons.local_shipping_outlined,
                              size: 14,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Proveedor: ${data.supplierName ?? 'sin asignar'}',
                              style: Theme.of(context).textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_canEditPrices)
                            Text('  editar',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.primary)),
                        ],
                      ),
                    ),
                  ),
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

  /// Precios por cantidad (mayoreo) del producto: lista de escalones y botón
  /// para editarlos. Aplica a todas las variantes, contando cantidad surtida.
  Widget _mayoreoCard(_EditorData data) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('Precios por cantidad (mayoreo)',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_canEditPrices)
                  TextButton(
                    onPressed: () => _editTiers(data),
                    child: Text(data.tiers.isEmpty ? 'Agregar' : 'Editar'),
                  ),
              ],
            ),
            if (data.tiers.isEmpty)
              Text(
                'Sin mayoreo. Agrega un escalón (p. ej. “desde 10 pzas → \$X”) '
                'y el precio bajará solo en la venta al alcanzar la cantidad.',
                style: theme.textTheme.bodySmall,
              )
            else
              ...data.tiers.map(
                (t) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Desde ${t.minQty} pzas  →  \$${(t.priceCents / 100).toStringAsFixed(2)} c/u',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTiers(_EditorData data) async {
    final result = await showDialog<List<({int minQty, int priceCents})>>(
      context: context,
      builder: (_) => _TiersDialog(
        productName: data.product.name,
        basePriceCents: data.product.basePriceCents,
        initial: data.tiers,
      ),
    );
    if (result == null) return;
    try {
      await _repo.setPriceTiers(
          actor: _actor, productId: data.product.id, tiers: result);
      _toast(result.isEmpty ? 'Mayoreo quitado' : 'Mayoreo guardado');
      _reload();
    } catch (e) {
      _toast('$e');
    }
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

// ===========================================================================
// Diálogo de precios por cantidad (mayoreo)
// ===========================================================================

class _TierRow {
  _TierRow({int? minQty, int? priceCents})
      : qty = TextEditingController(text: minQty?.toString() ?? ''),
        price = TextEditingController(
            text: priceCents == null
                ? ''
                : (priceCents / 100).toStringAsFixed(2));
  final TextEditingController qty;
  final TextEditingController price;

  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class _TiersDialog extends StatefulWidget {
  const _TiersDialog({
    required this.productName,
    required this.basePriceCents,
    required this.initial,
  });
  final String productName;
  final int basePriceCents;
  final List<PriceTier> initial;

  @override
  State<_TiersDialog> createState() => _TiersDialogState();
}

class _TiersDialogState extends State<_TiersDialog> {
  late final List<_TierRow> _rows = widget.initial.isEmpty
      ? [_TierRow()]
      : [
          for (final t in widget.initial)
            _TierRow(minQty: t.minQty, priceCents: t.priceCents),
        ];

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_TierRow()));

  void _removeRow(_TierRow r) => setState(() {
        _rows.remove(r);
        r.dispose();
      });

  /// Escalones válidos capturados (qty>1 y precio>=0). El repositorio deduplica
  /// por cantidad y descarta lo inválido; aquí solo filtramos lo vacío.
  List<({int minQty, int priceCents})> _collect() {
    final out = <({int minQty, int priceCents})>[];
    for (final r in _rows) {
      final qty = int.tryParse(r.qty.text.trim());
      final pesos = double.tryParse(r.price.text.trim());
      if (qty == null || pesos == null) continue;
      if (qty <= 1 || pesos < 0) continue;
      out.add((minQty: qty, priceCents: (pesos * 100).round()));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Precios por cantidad (mayoreo)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.productName}  ·  menudeo \$${(widget.basePriceCents / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final r in _rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text('Desde'),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: r.qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            isDense: true, hintText: 'pzas'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('→'),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: r.price,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            isDense: true, prefixText: '\$', hintText: 'c/u'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar escalón',
                      onPressed: () => _removeRow(r),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: const Text('Agregar escalón'),
              ),
            ),
            Text(
              'Tip: un solo escalón basta para mayoreo (ej. desde 10 → \$X). '
              'La cantidad se cuenta surtida entre tallas/colores del producto.',
              style: Theme.of(context).textTheme.bodySmall,
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
          onPressed: () => Navigator.of(context).pop(_collect()),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
