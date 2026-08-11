import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../services/catalog_sync_service.dart';

/// Admin → Catálogo web: fija el secreto de publicación y publica el catálogo
/// local a Supabase para que lo lea la tienda web.
class CatalogWebScreen extends StatefulWidget {
  const CatalogWebScreen({super.key});

  @override
  State<CatalogWebScreen> createState() => _CatalogWebScreenState();
}

class _CatalogWebScreenState extends State<CatalogWebScreen> {
  static const _secretKey = 'catalog_publish_secret';

  late final AppDatabase _db = context.read<AppDatabase>();
  late final CatalogSyncService _sync = CatalogSyncService(_db);
  final _secret = TextEditingController();
  bool _loading = true;
  bool _publishing = false;
  String? _status;
  String? _supabaseUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String?> _setting(String key) async {
    final row = await (_db.select(_db.appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    final v = row?.value.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> _load() async {
    _secret.text = await _setting(_secretKey) ?? '';
    _supabaseUrl = await _setting('supabase_url');
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSecret() async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: _secretKey, value: _secret.text.trim()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Secreto guardado')));
    }
  }

  Future<void> _publish() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty) {
      setState(() => _status = 'Primero pon el secreto de publicación.');
      return;
    }
    await _saveSecret();
    setState(() {
      _publishing = true;
      _status = null;
    });
    try {
      final n = await _sync.publish(secret);
      if (mounted) {
        setState(() => _status = '✓ Catálogo publicado: $n productos.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error al publicar: $e');
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo web')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Publicar catálogo',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Sube tus productos activos (con precios, mayoreo y '
                          'existencia) a la nube para que los vea la tienda web. '
                          'Vuelve a publicar cuando cambies precios o inventario.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (_supabaseUrl == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '⚠ Conexión a la nube no configurada. Ve a '
                              'Admin → Respaldo → Configurar conexión.',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _secret,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Secreto de publicación',
                    helperText:
                        'El mismo que pusiste en catalog_config en Supabase.',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.save_outlined),
                      tooltip: 'Guardar secreto',
                      onPressed: _saveSecret,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_publishing ? 'Publicando…' : 'Publicar catálogo'),
                ),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_status!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _status!.startsWith('✓')
                              ? Colors.green.shade700
                              : theme.colorScheme.error,
                        )),
                  ),
              ],
            ),
    );
  }
}
