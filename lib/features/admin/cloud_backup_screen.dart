import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
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
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _statusIcon(svc.state),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatBlock(
                          label: svc.lastBackupAt == null
                              ? 'Sin respaldos aún'
                              : 'Último respaldo: ${DateFormat('dd/MM/yyyy HH:mm').format(svc.lastBackupAt!)}',
                          value: _statusText(svc.state),
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  if (svc.lastError != null) ...[
                    const Divider(height: 20),
                    Text('Error: ${svc.lastError}',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SupabaseConfigScreen())),
              icon: const Icon(Icons.key_outlined),
              label: const Text('Configurar conexión (Supabase)'),
            ),
            const SizedBox(height: 16),
            if (svc.state == SyncState.disabled)
              const SurfaceCard(
                child: Text(
                  'El respaldo aún no está conectado. Toca "Configurar conexión '
                  '(Supabase)", pega la URL y la llave anon de tu proyecto, y '
                  'luego cierra y reabre la app — la conexión se lee al '
                  'arrancar. Sin esto, la app funciona 100% local.',
                ),
              )
            else ...[
              if (!svc.isClaimedCached) ...[
                _newTabletBanner(context),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    await svc.markClaimed();
                    svc.backupNow();
                  },
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Empezar a respaldar esta tablet'),
                ),
              ] else
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

  Widget _newTabletBanner(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.brassDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Esta tablet aún no respalda',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Si es una tablet NUEVA y ya tienes datos en la nube, restaura '
            'primero (abajo) para no perderlos. Si es tu tablet principal, '
            'toca "Empezar a respaldar esta tablet".',
          ),
        ],
      ),
    );
  }

  Widget _statusIcon(SyncState s) => switch (s) {
        SyncState.syncing =>
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SyncState.ok =>
          const Icon(Icons.cloud_done, color: AppColors.success),
        SyncState.error => const Icon(Icons.cloud_off, color: AppColors.danger),
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

/// Captura de la conexión a Supabase (URL + llave anon) **dentro de la app**, sin
/// recompilar. Se guarda en `app_settings` y el arranque la lee con prioridad
/// sobre el `.env`. Requiere reiniciar la app para conectar.
class SupabaseConfigScreen extends StatefulWidget {
  const SupabaseConfigScreen({super.key});

  @override
  State<SupabaseConfigScreen> createState() => _SupabaseConfigScreenState();
}

class _SupabaseConfigScreenState extends State<SupabaseConfigScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  static const _kUrl = 'supabase_url';
  static const _kAnon = 'supabase_anon';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<String?> _get(String k) async {
    final r = await (_db.select(_db.appSettings)..where((t) => t.key.equals(k)))
        .getSingleOrNull();
    return r?.value;
  }

  Future<void> _set(String k, String v) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: k, value: v),
        );
  }

  Future<void> _load() async {
    _url.text = (await _get(_kUrl)) ?? '';
    _key.text = (await _get(_kAnon)) ?? '';
    if (mounted) setState(() => _loaded = true);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _restartDialog({required String msg}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Guardado'),
        content: Text(msg),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    final key = _key.text.trim();
    if (!url.startsWith('http') || !url.contains('.')) {
      _toast('URL inválida (debe empezar con https:// …)');
      return;
    }
    if (key.length < 20) {
      _toast('La llave anon parece incompleta');
      return;
    }
    setState(() => _saving = true);
    await _set(_kUrl, url);
    await _set(_kAnon, key);
    if (!mounted) return;
    setState(() => _saving = false);
    await _restartDialog(
        msg: 'Conexión guardada. Cierra por completo la app y vuelve a abrirla '
            'para conectar con Supabase.\n\nRecuerda haber corrido el SQL de '
            'configuración (docs/supabase-setup.md) en ese proyecto.');
  }

  Future<void> _clear() async {
    await _set(_kUrl, '');
    await _set(_kAnon, '');
    _url.clear();
    _key.clear();
    await _restartDialog(
        msg: 'Conexión borrada. Al reiniciar, la app quedará 100% local '
            '(sin respaldo en la nube).');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conexión a Supabase')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Pega la URL y la llave anon de tu proyecto de Supabase '
                    '(Settings → API → Project URL y anon public). NO uses la '
                    'llave service_role. Al guardar, cierra y reabre la app para '
                    'que conecte.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Project URL',
                    hintText: 'https://xxxxx.supabase.co',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _key,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Llave anon (public)',
                    hintText: 'eyJhbGciOi...',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar conexión'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _saving ? null : _clear,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Quitar conexión (volver a local)'),
                ),
              ],
            ),
    );
  }
}
