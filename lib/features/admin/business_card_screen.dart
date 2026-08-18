import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../services/business_card_settings.dart';
import '../../services/catalog_sync_service.dart';
import '../../services/image_service.dart';
import 'banners_screen.dart';

/// Editor de la tarjeta digital: una página pública única
/// (`shelby-caps.pages.dev/tarjeta/`) con redes, envíos, forma de pago,
/// proceso de compra, promociones y la tarjeta de lealtad. El dueño la llena
/// aquí y aprieta "Guardar y publicar" — sin pedir ayuda para cambiar un
/// precio o un dato bancario.
///
/// Los banners que se deslizan (servicios de limpieza, promociones) **no se
/// suben aquí**: la tarjeta reusa los mismos que ya se administran en
/// Admin → Anuncios de la tienda, para no duplicar la subida de imágenes.
class BusinessCardScreen extends StatefulWidget {
  const BusinessCardScreen({super.key});

  @override
  State<BusinessCardScreen> createState() => _BusinessCardScreenState();
}

class _BusinessCardScreenState extends State<BusinessCardScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final BusinessCardSettings _settings = context.read<BusinessCardSettings>();
  final _images = ImageService();

  // Campos sueltos (la tarjeta es esto, no una entidad con id: se edita en
  // memoria y se guarda entera al publicar).
  final _whatsapp = TextEditingController();
  final _tiktok = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _location = TextEditingController();
  final _catalogUrl = TextEditingController();
  final _shippingNotice = TextEditingController();
  final _bank = TextEditingController();
  final _clabe = TextEditingController();
  final _account = TextEditingController();
  final _holder = TextEditingController();
  final _oxxoBank = TextEditingController();
  final _oxxoCard = TextEditingController();
  final _loyaltyText = TextEditingController();

  List<FaqItem> _faq = [];
  List<String> _steps = [];
  List<String> _promotions = [];
  String? _loyaltyImagePath;

  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _settings.load();
    final d = _settings.data;
    _whatsapp.text = d.socials.whatsapp;
    _tiktok.text = d.socials.tiktok;
    _facebook.text = d.socials.facebook;
    _instagram.text = d.socials.instagram;
    _location.text = d.socials.locationUrl;
    _catalogUrl.text =
        d.catalogUrl.isNotEmpty ? d.catalogUrl : await CatalogSyncService(_db).storeUrl();
    _shippingNotice.text = d.shippingNotice;
    _bank.text = d.bankTransfer.bank;
    _clabe.text = d.bankTransfer.clabe;
    _account.text = d.bankTransfer.accountNumber;
    _holder.text = d.bankTransfer.holder;
    _oxxoBank.text = d.oxxoDeposit.bank;
    _oxxoCard.text = d.oxxoDeposit.cardNumber;
    _loyaltyText.text = d.loyaltyText;
    _faq = List.of(d.shippingFaq);
    _steps = List.of(d.purchaseSteps);
    _promotions = List.of(d.promotions);
    _loyaltyImagePath = d.loyaltyImagePath;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [
      _whatsapp, _tiktok, _facebook, _instagram, _location, _catalogUrl,
      _shippingNotice, _bank, _clabe, _account, _holder, _oxxoBank, _oxxoCard,
      _loyaltyText,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  BusinessCardData _collect() => BusinessCardData(
        socials: CardSocials(
          whatsapp: _whatsapp.text.trim(),
          tiktok: _tiktok.text.trim(),
          facebook: _facebook.text.trim(),
          instagram: _instagram.text.trim(),
          locationUrl: _location.text.trim(),
        ),
        catalogUrl: _catalogUrl.text.trim(),
        shippingNotice: _shippingNotice.text.trim(),
        shippingFaq: _faq,
        purchaseSteps: _steps,
        bankTransfer: BankTransfer(
          bank: _bank.text.trim(),
          clabe: _clabe.text.trim(),
          accountNumber: _account.text.trim(),
          holder: _holder.text.trim(),
        ),
        oxxoDeposit: OxxoDeposit(
          bank: _oxxoBank.text.trim(),
          cardNumber: _oxxoCard.text.trim(),
        ),
        promotions: _promotions,
        loyaltyText: _loyaltyText.text.trim(),
        loyaltyImagePath: _loyaltyImagePath,
      );

  Future<void> _saveAndPublish() async {
    setState(() => _busy = true);
    try {
      await _settings.save(_collect());
      final ok = await _settings.publish();
      if (!mounted) return;
      _toast(ok
          ? 'Publicado ✓ — shelby-caps.pages.dev/tarjeta/'
          : 'Se guardó, pero no se pudo publicar: ${_settings.lastError}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Foto de lealtad ----
  Future<void> _pickLoyaltyPhoto() async {
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
    if (source == null) return;
    setState(() => _busy = true);
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 90);
      if (file == null) return;
      final path = await _images.saveOptimizedBytes(await file.readAsBytes());
      if (path == null) {
        _toast('La imagen no es válida');
        return;
      }
      final old = _loyaltyImagePath;
      setState(() => _loyaltyImagePath = path);
      if (old != null && !old.startsWith('http')) await _images.delete(old);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- Listas editables (FAQ, pasos, promociones): mismo patrón de diálogo
  // agregar/quitar que ya usa Admin → Anuncios de la tienda. ----

  Future<void> _addFaq() async {
    final q = TextEditingController();
    final a = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nueva pregunta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: q,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Pregunta')),
            const SizedBox(height: 10),
            TextField(
                controller: a,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Respuesta')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar')),
        ],
      ),
    );
    if (ok != true) return;
    final qt = q.text.trim(), at = a.text.trim();
    if (qt.isEmpty || at.isEmpty) return;
    setState(() => _faq = [..._faq, FaqItem(q: qt, a: at)]);
  }

  Future<void> _addLine(String title, String hint, List<String> target,
      void Function(List<String>) apply) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar')),
        ],
      ),
    );
    if (ok != true) return;
    final text = ctrl.text.trim();
    if (text.isEmpty) return;
    apply([...target, text]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tarjeta digital')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? .6 : 1,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const SurfaceCard(
                child: Text(
                  'Una sola página pública con todo lo que necesita alguien '
                  'antes de comprarte: redes, envíos, forma de pago y '
                  'promociones. Se publica en '
                  'shelby-caps.pages.dev/tarjeta/ al apretar el botón de '
                  'abajo.',
                ),
              ),
              const SizedBox(height: 20),

              const SectionHeader('Redes sociales'),
              SurfaceCard(
                child: Column(
                  children: [
                    _field(_whatsapp, 'WhatsApp', hint: '10 dígitos'),
                    _field(_tiktok, 'TikTok', hint: '@usuario o liga'),
                    _field(_facebook, 'Facebook', hint: 'liga a la página'),
                    _field(_instagram, 'Instagram', hint: '@usuario o liga'),
                    _field(_location, 'Ubicación', hint: 'liga de Google Maps'),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SectionHeader(
                'Banners (servicios de limpieza, promos)',
                action: TextButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BannersScreen())),
                  child: const Text('Administrar'),
                ),
              ),
              SurfaceCard(
                child: Text(
                  'La tarjeta muestra los mismos banners que ya rotan en la '
                  'tienda: se suben una sola vez, en Anuncios de la tienda.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),

              const SizedBox(height: 20),
              const SectionHeader('Catálogo de gorras'),
              SurfaceCard(child: _field(_catalogUrl, 'Liga del catálogo')),

              const SizedBox(height: 20),
              SectionHeader(
                'Dudas sobre envíos (${_faq.length})',
                action: TextButton.icon(
                  onPressed: _addFaq,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ),
              SurfaceCard(
                child: Column(
                  children: [
                    _field(_shippingNotice, 'Aviso destacado',
                        hint: '¡Los envíos salen el mismo día...!'),
                    const Divider(height: 20),
                    if (_faq.isEmpty)
                      const Text('Sin preguntas todavía.')
                    else
                      for (final it in _faq)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(it.q,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(it.a),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _faq = _faq.where((x) => x != it).toList()),
                          ),
                        ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SectionHeader(
                'Proceso de compra (${_steps.length})',
                action: TextButton.icon(
                  onPressed: () => _addLine(
                    'Nuevo paso',
                    'Ej. Realizas el pago de tu pedido',
                    _steps,
                    (v) => setState(() => _steps = v),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ),
              _numberedList(_steps, (v) => setState(() => _steps = v)),

              const SizedBox(height: 20),
              const SectionHeader('Datos de transferencia'),
              SurfaceCard(
                child: Column(
                  children: [
                    _field(_bank, 'Banco'),
                    _field(_clabe, 'CLABE'),
                    _field(_account, 'Número de cuenta'),
                    _field(_holder, 'Nombre del titular'),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              const SectionHeader('Depósito en OXXO / 7-Eleven'),
              SurfaceCard(
                child: Column(
                  children: [
                    _field(_oxxoBank, 'Banco'),
                    _field(_oxxoCard, 'Número de tarjeta'),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              SectionHeader(
                'Paquetes y promociones (${_promotions.length})',
                action: TextButton.icon(
                  onPressed: () => _addLine(
                    'Nueva promoción',
                    'Ej. 3x2 ALO y OC \$1,700',
                    _promotions,
                    (v) => setState(() => _promotions = v),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Agregar'),
                ),
              ),
              _bulletList(_promotions, (v) => setState(() => _promotions = v)),

              const SizedBox(height: 20),
              const SectionHeader('Tarjeta de lealtad'),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field(_loyaltyText, 'Texto',
                        hint: 'Explica la promo (no es un contador en vivo)',
                        lines: 3),
                    const SizedBox(height: 10),
                    if (_loyaltyImagePath != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.control),
                        child: Image(
                          image: productImageProvider(_loyaltyImagePath)!,
                          height: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickLoyaltyPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(_loyaltyImagePath == null
                          ? 'Subir foto de la tarjeta'
                          : 'Cambiar foto'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _saveAndPublish,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Guardar y publicar'),
              ),
              if (_settings.lastPublishedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Última publicación: ${_settings.lastPublishedAt}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }

  Widget _numberedList(List<String> items, void Function(List<String>) apply) {
    if (items.isEmpty) {
      return const SurfaceCard(child: Text('Sin pasos todavía.'));
    }
    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(items[i]),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  final next = List.of(items)..removeAt(i);
                  apply(next);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _bulletList(List<String> items, void Function(List<String>) apply) {
    if (items.isEmpty) {
      return const SurfaceCard(child: Text('Sin promociones todavía.'));
    }
    return SurfaceCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.local_offer_outlined),
              title: Text(items[i]),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  final next = List.of(items)..removeAt(i);
                  apply(next);
                },
              ),
            ),
        ],
      ),
    );
  }
}
