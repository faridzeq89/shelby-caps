import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/cloud_backup_service.dart';

class CloudBackupScreen extends StatelessWidget {
  const CloudBackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<CloudBackupService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo en la nube')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _statusIcon(svc.state),
                        const SizedBox(width: 8),
                        Text(_statusText(svc.state),
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(svc.lastBackupAt == null
                        ? 'Sin respaldos aún'
                        : 'Último respaldo: ${DateFormat('dd/MM/yyyy HH:mm').format(svc.lastBackupAt!)}'),
                    if (svc.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text('Error: ${svc.lastError}',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (svc.state == SyncState.disabled)
              const Text(
                'El respaldo no está configurado (falta .env con las llaves de '
                'Supabase, o no hay conexión).',
                textAlign: TextAlign.center,
              )
            else ...[
              FilledButton.icon(
                onPressed: svc.state == SyncState.syncing
                    ? null
                    : () => svc.backupNow(),
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Respaldar ahora'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmRestore(context, svc),
                icon: const Icon(Icons.cloud_download),
                label: const Text('Restaurar desde la nube'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(SyncState s) => switch (s) {
        SyncState.syncing =>
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SyncState.ok => const Icon(Icons.cloud_done, color: Colors.green),
        SyncState.error => const Icon(Icons.cloud_off, color: Colors.red),
        SyncState.disabled => const Icon(Icons.cloud_off),
        SyncState.idle => const Icon(Icons.cloud_queue),
      };

  String _statusText(SyncState s) => switch (s) {
        SyncState.syncing => 'Respaldando...',
        SyncState.ok => 'Respaldo al día',
        SyncState.error => 'Error de respaldo',
        SyncState.disabled => 'Respaldo deshabilitado',
        SyncState.idle => 'Listo para respaldar',
      };

  Future<void> _confirmRestore(
      BuildContext context, CloudBackupService svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar desde la nube'),
        content: const Text(
            'Esto REEMPLAZA los datos locales con el último respaldo de la nube. '
            'Úsalo en una tablet nueva o si perdiste datos. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await svc.restoreFromCloud();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          title: Text('Restaurado'),
          content: Text(
              'Cierra por completo la app y vuelve a abrirla para usar los '
              'datos restaurados.'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo restaurar: $e')));
      }
    }
  }
}
