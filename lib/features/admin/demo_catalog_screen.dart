import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/demo_catalog.dart';
import '../../data/local/database.dart';
import '../../services/auth_controller.dart';

/// Carga (o borra) un catálogo de gorras de ejemplo para poder probar el POS y
/// la tienda web con datos que se ven reales.
///
/// Es explícito y reversible a propósito: la app arranca con catálogo vacío
/// porque el dueño carga su mercancía; esto es una herramienta de prueba, no
/// una semilla automática.
class DemoCatalogScreen extends StatefulWidget {
  const DemoCatalogScreen({super.key});

  @override
  State<DemoCatalogScreen> createState() => _DemoCatalogScreenState();
}

class _DemoCatalogScreenState extends State<DemoCatalogScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final DemoCatalogService _demo = DemoCatalogService(_db);
  bool _busy = false;
  String? _status;

  Profile get _actor => context.read<AuthController>().currentUser!;

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body, String ok) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true), child: Text(ok)),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _load() async {
    if (await _demo.hasProducts()) {
      final ok = await _confirm(
        'Ya hay productos',
        'El catálogo no está vacío. Las gorras de prueba se AGREGAN a lo que ya '
            'existe, así que puedes terminar con productos repetidos. '
            '¿Continuar de todos modos?',
        'Agregar',
      );
      if (!ok) return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final n = await _demo.load(_actor);
      if (!mounted) return;
      setState(() => _status = '$n gorras de prueba cargadas con sus fotos.');
      _toast('Catálogo de prueba cargado');
    } catch (e) {
      if (mounted) setState(() => _status = 'No se pudo cargar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retire() async {
    final ok = await _confirm(
      'Retirar el catálogo',
      'Deja las existencias en cero, borra las fotos y el mayoreo, y archiva '
          'todos los productos activos: dejan de aparecer en Venta y en la '
          'tienda web.\n\n'
          'Los productos no se borran de la base y el historial de inventario '
          'se conserva (es un libro mayor que no se altera).',
      'Retirar',
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final n = await _demo.retire(_actor);
      if (!mounted) return;
      setState(() => _status =
          '$n productos archivados y sin existencias. Listo para cargar el real.');
      _toast('Catálogo retirado');
    } catch (e) {
      if (mounted) setState(() => _status = 'No se pudo retirar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de prueba')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SurfaceCard(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '24 gorras de ejemplo con nombres, precios, agotados y '
                  'escalones de mayoreo, cada una con varias vistas de foto.',
                ),
                SizedBox(height: 8),
                Text(
                  'Sirve para probar el POS y, al publicar, ver la tienda web '
                  'con el mismo contenido. Bórralo antes de cargar la '
                  'mercancía real.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _load,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            label: Text(_busy ? 'Trabajando…' : 'Cargar catálogo de prueba'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _retire,
            style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Retirar el catálogo'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            SurfaceCard(child: Text(_status!)),
          ],
        ],
      ),
    );
  }
}
