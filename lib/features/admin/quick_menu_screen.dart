import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/auth_controller.dart';
import '../../services/quick_menu.dart';
import '../home/quick_destinations.dart';

/// Elige qué botones salen en la barra de abajo y en qué orden.
///
/// Cada tienda usa la app distinto: una vive en Vender y Balance, otra necesita
/// Apartados a la mano. Por eso lo decide el dueño.
class QuickMenuScreen extends StatefulWidget {
  const QuickMenuScreen({super.key});

  @override
  State<QuickMenuScreen> createState() => _QuickMenuScreenState();
}

class _QuickMenuScreenState extends State<QuickMenuScreen> {
  late List<String> _selected = List.of(context.read<QuickMenu>().ids);

  bool get _isAdmin => context.read<AuthController>().isAdmin;

  Future<void> _persist() => context.read<QuickMenu>().save(_selected);

  void _toggle(String id, bool on) {
    setState(() {
      if (on) {
        if (!_selected.contains(id)) _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
    _persist();
  }

  /// `onReorderItem` ya entrega el índice destino corregido, así que aquí no
  /// hay que descontarle uno como pedía el `onReorder` viejo.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _selected.insert(newIndex, _selected.removeAt(oldIndex));
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disponibles = quickDestinations
        .where((d) => (!d.adminOnly || _isAdmin) && !_selected.contains(d.id))
        .toList();
    final conEtiqueta = _selected.length <= QuickMenu.labelLimit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menú rápido'),
        actions: [
          TextButton(
            onPressed: () async {
              await context.read<QuickMenu>().reset();
              if (mounted) {
                setState(() => _selected = List.of(QuickMenu.defaults));
              }
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Elige los botones de la barra de abajo. Arrastra para '
                  'cambiar el orden.',
                ),
                const SizedBox(height: 8),
                Text(
                  conEtiqueta
                      ? 'Con ${_selected.length} botones se ve el ícono y el '
                          'nombre. Del quinto en adelante, solo el ícono.'
                      : 'Con ${_selected.length} botones se ve solo el ícono: '
                          'los nombres ya no caben sin cortarse.',
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader('En la barra (${_selected.length})'),
          if (_selected.isEmpty)
            const SurfaceCard(
              child: Text('Sin botones. Se usarán los de fábrica.'),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: _reorder,
              children: [
                for (var i = 0; i < _selected.length; i++)
                  _tile(_selected[i], i),
              ],
            ),
          const SizedBox(height: 20),
          const SectionHeader('Disponibles'),
          if (disponibles.isEmpty)
            const SurfaceCard(child: Text('Ya están todos en la barra.'))
          else
            for (final d in disponibles)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfaceCard(
                  onTap: () => _toggle(d.id, true),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(d.icon, color: theme.hintColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(d.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      const Icon(Icons.add, color: AppColors.brassDeep),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _tile(String id, int index) {
    final d = destinationById(id);
    final theme = Theme.of(context);
    if (d == null) {
      // Un id desconocido (config vieja tras actualizar) no debe romper nada.
      return SizedBox.shrink(key: ValueKey('desconocido-$id'));
    }
    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(d.selectedIcon, color: AppColors.brassDeep),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.label,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (!d.isTab)
                    Text('Atajo: abre la pantalla',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              color: theme.colorScheme.error,
              onPressed: () => _toggle(id, false),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(Icons.drag_handle, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
