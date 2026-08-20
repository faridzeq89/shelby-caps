import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/catalog_sync_service.dart';

/// Catálogo → Categorías. Crear, renombrar, **acomodar a mano**, archivar y
/// eliminar.
///
/// El orden es lo que el dueño pidió el 20 ago 2026: el renglón se arrastra y
/// ese es el orden con el que salen las categorías en el mostrador **y en la
/// tienda web**. Antes la tienda las acomodaba alfabéticamente (las deducía de
/// los productos publicados), así que lo que más vende quedaba al final por
/// empezar con la letra equivocada.
///
/// Eliminar: borrado real si no le cuelga ningún producto. Con productos no se
/// borra en cascada —`category_id` es obligatorio y los dejaría huérfanos—, así
/// que se archiva: deja de ofrecerse y de aparecer en la tienda, y sus productos
/// siguen a la venta.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final CatalogRepository _repo =
      CatalogRepository(context.read<AppDatabase>());

  List<Category> _cats = [];
  Map<int, int> _counts = {};
  bool _cargando = true;

  Profile get _actor => context.read<AuthController>().currentUser!;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final cats = await _repo.categories();
    final counts = await _repo.categoryProductCounts();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _counts = counts;
      _cargando = false;
    });
  }

  /// Publica ya, sin esperar el retraso: el orden y los nombres son lo que ve el
  /// cliente en la tienda, y el dueño acaba de acomodarlos mirando la pantalla.
  void _publicar() {
    unawaited(context.read<CatalogSyncService>().publishNow());
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _recargarYPublicar(String msg) async {
    await _cargar();
    _publicar();
    _toast(msg);
  }

  // --------------------------------------------------------------------------
  // Acciones
  // --------------------------------------------------------------------------

  Future<void> _nueva() async {
    final nombre = await _pedirNombre(titulo: 'Nueva categoría');
    if (nombre == null) return;
    try {
      await _repo.createCategory(_actor, nombre);
      await _recargarYPublicar('Categoría creada');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _renombrar(Category c) async {
    final nombre =
        await _pedirNombre(titulo: 'Renombrar categoría', inicial: c.name);
    if (nombre == null || nombre == c.name) return;
    try {
      await _repo.renameCategory(_actor, c.id, nombre);
      await _recargarYPublicar('Categoría renombrada');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _archivar(Category c) async {
    try {
      await _repo.setCategoryActive(_actor, c.id, !c.active);
      await _recargarYPublicar(
          c.active ? 'Categoría archivada' : 'Categoría reactivada');
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _eliminar(Category c) async {
    final productos = _counts[c.id] ?? 0;
    final tieneProductos = productos > 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(tieneProductos
            ? '"${c.name}" tiene $productos '
                'producto${productos == 1 ? '' : 's'}. Borrarla los dejaría sin '
                'categoría, así que se ARCHIVA: deja de aparecer al filtrar, al '
                'dar de alta un producto y en la tienda, pero esos productos '
                'siguen a la venta y conservan su nombre. ¿Continuar?'
            : '¿Borrar la categoría "${c.name}" de forma permanente? No tiene '
                'productos, así que no se pierde nada más.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            style: tieneProductos
                ? null
                : FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tieneProductos ? 'Archivar' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deleteCategory(_actor, c.id);
      await _recargarYPublicar(
          tieneProductos ? 'Categoría archivada' : 'Categoría eliminada');
    } catch (e) {
      _toast('$e');
    }
  }

  /// Arrastrar y soltar. Se reacomoda en pantalla y se guarda el orden completo:
  /// `sort_order` queda 0, 1, 2… como quedó la lista. [to] ya viene ajustado
  /// (`onReorderItem`, no el `onReorder` viejo que lo mandaba corrido en uno).
  Future<void> _mover(int from, int to) async {
    final lista = [..._cats];
    final movida = lista.removeAt(from);
    lista.insert(to, movida);
    setState(() => _cats = lista);
    try {
      await _repo.reorderCategories(_actor, [for (final c in lista) c.id]);
      _publicar();
    } catch (e) {
      _toast('$e');
      await _cargar();
    }
  }

  Future<String?> _pedirNombre({required String titulo, String? inicial}) {
    final ctrl = TextEditingController(text: inicial ?? '');
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Nombre', hintText: 'NEW ERA, ORIGINALES, LIMPIEZA…'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    ).then((v) => (v == null || v.isEmpty) ? null : v);
  }

  // --------------------------------------------------------------------------
  // Vista
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            tooltip: 'Nueva categoría',
            onPressed: _nueva,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _cats.isEmpty
              ? EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'Sin categorías',
                  hint: 'Las categorías agrupan la mercancía en el mostrador y '
                      'son los botones de la tienda en línea.',
                  action: FilledButton.icon(
                    onPressed: _nueva,
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva categoría'),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: SurfaceCard(
                        child: Row(
                          children: [
                            Icon(Icons.swap_vert, color: AppColors.accent),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Arrastra para acomodarlas. Este es el orden con '
                                'el que salen en la tienda en línea: lo que más '
                                'vendes, primero.',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _cats.length,
                        onReorderItem: _mover,
                        itemBuilder: (context, i) => _renglon(_cats[i], i),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _renglon(Category c, int index) {
    final productos = _counts[c.id] ?? 0;
    return Padding(
      key: ValueKey(c.id),
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.drag_handle),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(c.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                      if (!c.active) ...[
                        const SizedBox(width: 8),
                        const StatusPill('ARCHIVADA'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    productos == 0
                        ? 'Sin productos'
                        : '$productos producto${productos == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (v) {
                switch (v) {
                  case 'rename':
                    _renombrar(c);
                  case 'archive':
                    _archivar(c);
                  case 'delete':
                    _eliminar(c);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(
                    value: 'archive',
                    child: Text(c.active ? 'Archivar' : 'Reactivar')),
                const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
