import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/local/open_db.dart';
import '../../services/catalog_sync_service.dart';

/// Puente web → app nativa. Sube una copia **completa** de la base local (drift
/// `exportDatabase`) al mismo `backups/boutique.sqlite` que la app nativa lee con
/// "Restaurar desde la nube". Así, al instalar la app de iPhone en el mismo
/// aparato, el cliente recupera TODO (productos, ventas, inventario, clientes…),
/// que de otro modo no viaja (Safari y la app nativa son cajas separadas).
///
/// **No borra nada local**: es una copia. Como exportar exige soltar el candado
/// de OPFS, se cierra la base y la página se reinicia al terminar (reabre la
/// misma base intacta).
class MigrateToAppScreen extends StatefulWidget {
  const MigrateToAppScreen({super.key});

  @override
  State<MigrateToAppScreen> createState() => _MigrateToAppScreenState();
}

class _MigrateToAppScreenState extends State<MigrateToAppScreen> {
  static const _bucket = 'backups';
  static const _object = 'boutique.sqlite';
  bool _busy = false;

  Future<void> _migrate() async {
    // Se toman los servicios ANTES de cualquier await (no usar context después).
    final db = context.read<AppDatabase>();
    final connected = context.read<CatalogSyncService>().available;
    if (!connected) {
      _toast('Sin conexión a Supabase. Revisa Respaldo → Configurar conexión.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Subir a la nube'),
        content: const Text(
            'Se sube una copia de TODA tu información a la nube para pasarla a '
            'la app de iPhone. Tus datos aquí NO se borran. Al terminar, la '
            'página se reinicia sola. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Subir')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    String? error;
    var sizeKb = 0;
    try {
      // Cerrar suelta el candado de OPFS para poder exportar la base.
      await db.close();
      final bytes = await exportDatabaseBytes();
      sizeKb = (bytes.length / 1024).round();
      await Supabase.instance.client.storage.from(_bucket).uploadBinary(
            _object,
            bytes,
            fileOptions: const FileOptions(
                upsert: true, contentType: 'application/octet-stream'),
          );
    } catch (e) {
      error = '$e';
    }

    if (!mounted) {
      reloadApp();
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(error == null ? 'Listo ✓' : 'No se pudo'),
        content: Text(error == null
            ? 'Tu información ya está en la nube ($sizeKb KB). En el iPhone, '
                'instala la app, entra a Respaldo → "Restaurar desde la nube" y '
                'tendrás todo aquí.\n\nToca para reiniciar esta página.'
            : 'No se pudo subir: $error\n\nToca para reiniciar e intentar de '
                'nuevo.'),
        actions: [
          FilledButton(
            onPressed: () => reloadApp(),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    // Por si el diálogo se cerrara de otra forma: la base quedó cerrada, hay que
    // reabrir la app.
    reloadApp();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pasar a la app de iPhone')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Para qué es esto?',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  SizedBox(height: 8),
                  Text(
                    'Esta versión web guarda todo dentro de Safari. La app de '
                    'iPhone (cuando la instales) usa su propia caja y no ve lo de '
                    'Safari. Este botón sube una copia de TODO a la nube para que '
                    'la app la baje con "Restaurar desde la nube".',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _step('1.', 'Toca "Subir mi información a la nube" (aquí).'),
                  _step('2.', 'Instala la app de iPhone en este mismo teléfono.'),
                  _step('3.',
                      'En la app: Menú → Respaldo → "Restaurar desde la nube".'),
                  _step('4.', 'Cierra y reabre la app: ahí está todo tu trabajo.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfaceCard(
              child: Text(
                'Tus datos en esta web NO se borran; es una copia. Al terminar, '
                'la página se reinicia sola.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _migrate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_busy ? 'Subiendo…' : 'Subir mi información a la nube'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
