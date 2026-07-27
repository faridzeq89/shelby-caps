import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_dropdown.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/image_service.dart';
import 'import_screen.dart';
import 'product_editor_screen.dart';

class CatalogHomeScreen extends StatefulWidget {
  const CatalogHomeScreen({super.key});

  @override
  State<CatalogHomeScreen> createState() => _CatalogHomeScreenState();
}

class _CatalogData {
  _CatalogData(this.products, this.categoryNames, this.variantCounts);
  final List<Product> products;
  final Map<int, String> categoryNames;
  final Map<int, int> variantCounts;
}

class _CatalogHomeScreenState extends State<CatalogHomeScreen> {
  late final CatalogRepository _repo =
      CatalogRepository(context.read<AppDatabase>());
  late Future<_CatalogData> _future = _load();

  String _query = '';
  int? _categoryFilter; // null = todas

  Profile get _actor => context.read<AuthController>().currentUser!;

  Future<_CatalogData> _load() async {
    final products = await _repo.products();
    final categories = {
      for (final c in await _repo.categories()) c.id: c.name,
    };
    final counts = <int, int>{};
    for (final p in products) {
      counts[p.id] = (await _repo.variantsOf(p.id)).length;
    }
    return _CatalogData(products, categories, counts);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _newProduct() async {
    final productId = await showDialog<int>(
      context: context,
      builder: (_) => _NewProductDialog(repo: _repo, actor: _actor),
    );
    if (productId == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductEditorScreen(productId: productId),
    ));
    _reload();
  }

  Future<void> _openProduct(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProductEditorScreen(productId: id),
    ));
    _reload();
  }

  Widget _categoryChips(Map<int, String> categories) {
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
              onSelected: (_) => setState(() => _categoryFilter = null),
            ),
          ),
          for (final e in categories.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.value),
                selected: _categoryFilter == e.key,
                onSelected: (_) => setState(() => _categoryFilter = e.key),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo'),
        actions: [
          IconButton(
            tooltip: 'Importar desde CSV/Excel',
            icon: const Icon(Icons.upload_file),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ImportScreen(),
              ));
              _reload();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newProduct,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      body: FutureBuilder<_CatalogData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          if (data.products.isEmpty) {
            return const Center(
              child: Text('Sin productos todavía.\nToca "Nuevo producto".',
                  textAlign: TextAlign.center),
            );
          }
          final q = _query.trim().toLowerCase();
          final products = data.products.where((p) {
            if (_categoryFilter != null && p.categoryId != _categoryFilter) {
              return false;
            }
            if (q.isNotEmpty && !p.name.toLowerCase().contains(q)) return false;
            return true;
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar producto…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              _categoryChips(data.categoryNames),
              Expanded(
                child: products.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisExtent: 232,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: products.length,
                        itemBuilder: (context, i) {
                          final p = products[i];
                          return _CatalogTile(
                            product: p,
                            category: data.categoryNames[p.categoryId] ?? '—',
                            variantCount: data.variantCounts[p.id] ?? 0,
                            onTap: () => _openProduct(p.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Mosaico de producto con foto (o marcador), nombre, categoría/variantes y precio.
class _CatalogTile extends StatelessWidget {
  const _CatalogTile({
    required this.product,
    required this.category,
    required this.variantCount,
    required this.onTap,
  });
  final Product product;
  final String category;
  final int variantCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = productImageProvider(product.imagePath);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: provider != null
                  ? Image(
                      image: ResizeImage(provider,
                          width: 360, allowUpscaling: false),
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
                  Text('$category · $variantCount var.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                  Text('\$${(product.basePriceCents / 100).toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600)),
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

/// Alta de producto: nombre, categoría (existente o nueva), marca y precio base.
class _NewProductDialog extends StatefulWidget {
  const _NewProductDialog({required this.repo, required this.actor});
  final CatalogRepository repo;
  final Profile actor;

  @override
  State<_NewProductDialog> createState() => _NewProductDialogState();
}

class _NewProductDialogState extends State<_NewProductDialog> {
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _price = TextEditingController();
  final _newCategory = TextEditingController();
  List<Category> _categories = [];
  int? _categoryId;
  bool _creatingCategory = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.repo.categories().then((c) {
      if (!mounted) return;
      setState(() {
        _categories = c;
        _categoryId = c.isNotEmpty ? c.first.id : null;
        _creatingCategory = c.isEmpty;
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _price.dispose();
    _newCategory.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final priceCents = ((double.tryParse(_price.text.trim()) ?? -1) * 100).round();
    if (name.isEmpty || priceCents < 0) {
      setState(() => _error = 'Nombre y precio válido son obligatorios');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var categoryId = _categoryId;
      if (_creatingCategory) {
        final catName = _newCategory.text.trim();
        if (catName.isEmpty) {
          setState(() {
            _saving = false;
            _error = 'Escribe el nombre de la categoría';
          });
          return;
        }
        categoryId = await widget.repo.createCategory(widget.actor, catName);
      }
      final id = await widget.repo.createProduct(
        widget.actor,
        name: name,
        categoryId: categoryId!,
        basePriceCents: priceCents,
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo producto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brand,
              decoration: const InputDecoration(labelText: 'Marca (opcional)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Precio base', prefixText: '\$'),
            ),
            const SizedBox(height: 16),
            if (!_creatingCategory)
              Row(
                children: [
                  Expanded(
                    child: AppDropdown<int>(
                      label: 'Categoría',
                      value: _categoryId,
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Nueva categoría',
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _creatingCategory = true),
                  ),
                ],
              )
            else
              TextField(
                controller: _newCategory,
                decoration:
                    const InputDecoration(labelText: 'Nueva categoría'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
