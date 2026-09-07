import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/business_card_settings.dart';
import '../../services/image_service.dart';

/// Editor de la **tira de anuncios** de la tienda (la barra que va debajo del
/// horario, con mensajes que rotan). Cada anuncio tiene un texto, una imagen
/// pequeña opcional (logo/ícono) y un enlace opcional.
///
/// Se guarda en el mismo JSON de la tarjeta digital (`business_card`) y se
/// publica con el mismo mecanismo — sin tabla ni migración nuevas. La tienda lo
/// lee y, si está vacío, cae a los ejemplos de `web-catalogo/config.js`.
class StoreTickerScreen extends StatefulWidget {
  const StoreTickerScreen({super.key});

  @override
  State<StoreTickerScreen> createState() => _StoreTickerScreenState();
}

class _StoreTickerScreenState extends State<StoreTickerScreen> {
  late final BusinessCardSettings _settings =
      context.read<BusinessCardSettings>();
  final _images = ImageService();

  List<CardTicker> _items = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    if (!mounted) return;
    setState(() {
      _items = List.of(_settings.data.ticker);
      _loading = false;
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _pickImage() async {
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
    final file =
        await ImagePicker().pickImage(source: source, maxWidth: 400, imageQuality: 90);
    if (file == null) return null;
    final path = await _images.saveOptimizedBytes(await file.readAsBytes());
    if (path == null) _toast('La imagen no es válida');
    return path;
  }

  Future<void> _edit([int? index]) async {
    final res = await showDialog<CardTicker>(
      context: context,
      builder: (_) => _TickerItemDialog(
        item: index == null ? null : _items[index],
        pickImage: _pickImage,
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (index == null) {
        _items.add(res);
      } else {
        _items[index] = res;
      }
    });
  }

  void _remove(int index) => setState(() => _items.removeAt(index));

  Future<void> _saveAndPublish() async {
    setState(() => _busy = true);
    try {
      await _settings.save(_settings.data.copyWith(ticker: _items));
      final ok = await _settings.publish();
      if (!mounted) return;
      _toast(ok
          ? 'Publicado ✓ — se ve en shelby-caps.pages.dev'
          : 'Se guardó, pero no se pudo publicar: ${_settings.lastError}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tira de anuncios')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Text(
                    'Mensajes cortos que rotan solos debajo del horario en la '
                    'tienda. Arrastra para reordenar. Toca uno para editarlo.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(
                          icon: Icons.campaign_outlined,
                          title: 'Sin anuncios en la tira',
                          hint: 'Toca "Agregar" para poner un mensaje. Sin '
                              'anuncios, la tienda usa los de ejemplo.',
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 92),
                          itemCount: _items.length,
                          // ignore: deprecated_member_use
                          onReorder: (oldI, newI) => setState(() {
                            if (newI > oldI) newI -= 1;
                            final it = _items.removeAt(oldI);
                            _items.insert(newI, it);
                          }),
                          itemBuilder: (context, i) {
                            final t = _items[i];
                            final prov = t.image.isEmpty
                                ? null
                                : productImageProvider(t.image);
                            return Padding(
                              key: ValueKey('tk_$i-${t.text}'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SurfaceCard(
                                padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(Icons.drag_handle,
                                            color: Colors.grey),
                                      ),
                                    ),
                                    if (prov != null)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image(
                                            image: prov,
                                            width: 34,
                                            height: 34,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(t.text,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          if (t.link.isNotEmpty)
                                            Text(t.link,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Editar',
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 20),
                                      onPressed: () => _edit(i),
                                    ),
                                    IconButton(
                                      tooltip: 'Quitar',
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20),
                                      onPressed: () => _remove(i),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _saveAndPublish,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(_busy ? 'Publicando…' : 'Guardar y publicar'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Diálogo para crear o editar un anuncio de la tira.
class _TickerItemDialog extends StatefulWidget {
  const _TickerItemDialog({required this.item, required this.pickImage});
  final CardTicker? item;
  final Future<String?> Function() pickImage;

  @override
  State<_TickerItemDialog> createState() => _TickerItemDialogState();
}

class _TickerItemDialogState extends State<_TickerItemDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.item?.text ?? '');
  late final TextEditingController _link =
      TextEditingController(text: widget.item?.link ?? '');
  late String _image = widget.item?.image ?? '';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = _image.isEmpty ? null : productImageProvider(_image);
    return AlertDialog(
      title: Text(widget.item == null ? 'Nuevo anuncio' : 'Editar anuncio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 1,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Texto del anuncio',
                hintText: 'Ej. Envíos el mismo día',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace (opcional)',
                hintText: 'https://…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (prov != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image(
                          image: prov, width: 44, height: 44, fit: BoxFit.contain),
                    ),
                  ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final path = await widget.pickImage();
                            if (!mounted) return;
                            setState(() {
                              if (path != null) _image = path;
                              _busy = false;
                            });
                          },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_image.isEmpty
                        ? 'Imagen pequeña (opcional)'
                        : 'Cambiar imagen'),
                  ),
                ),
                if (_image.isNotEmpty)
                  IconButton(
                    tooltip: 'Quitar imagen',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _image = ''),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    CardTicker(
                      text: _text.text.trim(),
                      image: _image,
                      link: _link.text.trim(),
                    ),
                  ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
