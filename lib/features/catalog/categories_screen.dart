import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../services/auth_controller.dart';

/// Gestión de categorías: eliminar (o archivar si tienen productos) y
/// reactivar. El alta de categorías sigue haciéndose al dar de alta un
/// producto.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final CatalogRepository _repo =
      CatalogRepository(context.read<AppDatabase>());
  late Future<List<Category>> _future = _repo.categories();

  Profile get _actor => context.read<AuthController>().currentUser!;

  void _reload() => setState(() => _future = _repo.categories());

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _delete(Category c) async {
    final hasProducts = await _repo.categoryHasProducts(c.id);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(hasProducts
            ? '"${c.name}" tiene productos. Borrarla los dejaría sin '
                'categoría, así que se ARCHIVA: deja de aparecer al filtrar o '
                'dar de alta un producto, pero los productos que ya la tienen '
                'conservan su nombre. ¿Continuar?'
            : '¿Borrar la categoría "${c.name}" de forma permanente? No tiene '
                'productos, así que se elimina por completo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: hasProducts
                ? null
                : FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(hasProducts ? 'Archivar' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deleteCategory(_actor, c.id);
      _toast(hasProducts ? 'Categoría archivada' : 'Categoría eliminada');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _reactivate(Category c) async {
    try {
      await _repo.setCategoryActive(_actor, c.id, true);
      _toast('Categoría reactivada');
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      body: FutureBuilder<List<Category>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snap.data!;
          if (categories.isEmpty) {
            return const EmptyState(
              icon: Icons.sell_outlined,
              title: 'Sin categorías',
              hint: 'Se crean al dar de alta un producto nuevo.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final c = categories[i];
              return SurfaceCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(c.name,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                          if (!c.active) ...[
                            const SizedBox(width: 8),
                            const StatusPill('ARCHIVADA'),
                          ],
                        ],
                      ),
                    ),
                    if (c.active)
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(c),
                      )
                    else
                      TextButton(
                        onPressed: () => _reactivate(c),
                        child: const Text('Reactivar'),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
