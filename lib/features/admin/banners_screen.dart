import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/banner_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/image_service.dart';

/// Anuncios de la tienda en línea: la portada y los banners que rotan.
///
/// Todo se publica solo, igual que el catálogo: el dueño sube una imagen desde
/// el celular y en menos de un minuto está en la tienda, sin tocar código ni
/// correr comandos.
class BannersScreen extends StatefulWidget {
  const BannersScreen({super.key});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

class _Data {
  _Data(this.cover, this.banners);
  final StoreBanner? cover;
  final List<StoreBanner> banners;
}

class _BannersScreenState extends State<BannersScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final BannerRepository _repo = BannerRepository(_db);
  final ImageService _images = ImageService();
  late Future<_Data> _future = _load();
  bool _busy = false;

  Profile get _actor => context.read<AuthController>().currentUser!;

  Future<_Data> _load() async =>
      _Data(await _repo.cover(), await _repo.banners());

  void _reload() {
    setState(() => _future = _load());
    // Publica de INMEDIATO (no con el retraso de 20 s): en el navegador ese
    // temporizador se congela al cambiar de pestaña o ir a la tienda, y el
    // banner nunca subía. Además mostramos el resultado para que un fallo no
    // pase inadvertido.
    final sync = context.read<CatalogSyncService>();
    setState(() => _busy = true);
    unawaited(sync.publishNow().whenComplete(() {
      if (!mounted) return;
      setState(() => _busy = false);
      // En éxito, mensaje simple. Si falla, incluye la pista técnica.
      _toast(sync.lastError == null
          ? 'Publicado en la tienda ✓'
          : 'No se pudo publicar: ${sync.lastError}'
              '${sync.dbgBannerNote != null ? ' · ${sync.dbgBannerNote}' : ''}');
    }));
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Toma o elige una imagen y la guarda optimizada.
  Future<String?> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 90);
      if (file == null) return null;
      final path = await _images.saveOptimizedBytes(await file.readAsBytes());
      if (path == null) _toast('La imagen no es válida');
      return path;
    } catch (e) {
      _toast('No se pudo abrir la galería: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBanner() async {
    final path = await _pick();
    if (path == null) return;
    final caption = await _askCaption();
    try {
      await _repo.addBanner(_actor, path: path, caption: caption);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _setCover() async {
    final path = await _pick();
    if (path == null) return;
    try {
      final old = await _repo.setCover(_actor, path: path);
      await _images.delete(old);
      _reload();
    } catch (e) {
      _toast('$e');
    }
  }

  /// Texto corto del anuncio: sirve para acordarse de cuál es y para quien
  /// navega con lector de pantalla.
  Future<String?> _askCaption() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿De qué es el anuncio?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej. 3x2 en réplicas',
            helperText: 'Opcional. No se ve encima de la imagen.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Saltar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    final text = ctrl.text.trim();
    return (ok == true && text.isNotEmpty) ? text : null;
  }

  Future<void> _remove(StoreBanner b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(b.isCover ? 'Quitar la portada' : 'Quitar el anuncio'),
        content: const Text('Deja de verse en la tienda. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    final path = await _repo.remove(_actor, b.id);
    await _images.delete(path);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Anuncios de la tienda')),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SurfaceCard(
                child: Text(
                  'La portada va hasta arriba del catálogo. Los anuncios rotan '
                  'solos abajo de ella. Se publican en menos de un minuto, sin '
                  'apretar nada más.\n\n'
                  'Las imágenes se ven mejor apaisadas: la portada a 1200×420 '
                  'y los anuncios a 900×360.',
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader('Portada'),
              if (data.cover == null)
                _emptySlot('Sin portada', 'Poner portada', _setCover)
              else
                _tile(data.cover!, isCover: true),
              const SizedBox(height: 20),
              SectionHeader(
                'Anuncios (${data.banners.length})',
                action: TextButton.icon(
                  onPressed: _busy ? null : _addBanner,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ),
              if (data.banners.isEmpty)
                SurfaceCard(
                  child: Text(
                    'Sin anuncios propios. Mientras no subas ninguno, la tienda '
                    'muestra los de ejemplo.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else
                for (final b in data.banners) _tile(b),
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _emptySlot(String title, String action, VoidCallback onTap) {
    return SurfaceCard(
      onTap: _busy ? null : onTap,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.add_photo_alternate_outlined,
              size: 36, color: AppColors.brassDeep),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(action,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.brassDeep)),
        ],
      ),
    );
  }

  Widget _tile(StoreBanner b, {bool isCover = false}) {
    final theme = Theme.of(context);
    final provider = productImageProvider(b.path);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: isCover ? 1200 / 420 : 900 / 360,
              child: provider == null
                  ? Container(color: theme.colorScheme.surfaceContainerHighest)
                  : Image(image: provider, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.caption ?? (isCover ? 'Portada' : 'Sin descripción'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: b.caption == null
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  if (!isCover) ...[
                    IconButton(
                      tooltip: b.active ? 'Apagar' : 'Prender',
                      icon: Icon(b.active
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      color: b.active ? AppColors.success : theme.hintColor,
                      onPressed: () async {
                        await _repo.setActive(_actor, b.id, !b.active);
                        _reload();
                      },
                    ),
                    IconButton(
                      tooltip: 'Subir',
                      icon: const Icon(Icons.arrow_upward, size: 20),
                      onPressed: () async {
                        await _repo.move(_actor, b.id, -1);
                        _reload();
                      },
                    ),
                    IconButton(
                      tooltip: 'Bajar',
                      icon: const Icon(Icons.arrow_downward, size: 20),
                      onPressed: () async {
                        await _repo.move(_actor, b.id, 1);
                        _reload();
                      },
                    ),
                  ] else
                    TextButton(
                        onPressed: _busy ? null : _setCover,
                        child: const Text('Cambiar')),
                  IconButton(
                    tooltip: 'Quitar',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => _remove(b),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
