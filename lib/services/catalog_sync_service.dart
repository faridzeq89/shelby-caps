import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../data/repositories/banner_repository.dart';
import '../data/repositories/catalog_repository.dart';
import 'image_service.dart';

/// El catálogo listo para publicar, ya como JSON (listas de mapas) que la
/// función `publish_catalog` de Supabase espera.
class CatalogSnapshot {
  const CatalogSnapshot(this.products, this.variants, this.tiers);
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> tiers;
  int get productCount => products.length;
  int get variantCount => variants.length;
}

/// Publica el catálogo local a Supabase para la tienda web. Reusa el cliente
/// global (`Supabase.instance`) y la función segura `publish_catalog` (que valida
/// un secreto). El precio publicado de cada variante es su precio de menudeo
/// efectivo; el mayoreo va aparte en [CatalogSnapshot.tiers] para que la web lo
/// aplique igual que el POS.
class CatalogSyncService {
  CatalogSyncService(this._db);
  final AppDatabase _db;

  /// Clave donde vive el secreto de publicación dentro de la app.
  static const secretKey = 'catalog_publish_secret';

  /// Secreto con el que sale configurada la tienda. Está aquí para que el dueño
  /// **nunca tenga que escribirlo**: publicar debe ser invisible.
  ///
  /// Compromiso conocido: quien desarme el APK puede leerlo y reescribir el
  /// catálogo publicado (no toca ventas, inventario ni respaldos, que viven en
  /// la tablet). Si algún día importa, se cambia en Supabase con el último
  /// bloque de `0002_catalog.sql` y aquí.
  static const defaultSecret = 'shelby-caps-pub-JbmEwZJoRO9iHziGTVvtFlj5lNc4KJwE';

  /// Espera antes de publicar tras un cambio. Una venta toca varias tablas y el
  /// dueño suele editar varias cosas seguidas: con esto se publica una vez, no
  /// veinte.
  static const _debounce = Duration(seconds: 20);

  Timer? _timer;
  bool _publishing = false;

  /// Último resultado, para que la pantalla de catálogo pueda mostrarlo.
  DateTime? lastPublishedAt;
  String? lastError;

  SupabaseClient get _client => Supabase.instance.client;

  /// ¿Hay conexión a Supabase? Sin ella la tienda simplemente no se actualiza.
  bool get available => _supabaseReady();

  bool _supabaseReady() {
    try {
      // Acceder al cliente lanza si `Supabase.initialize` nunca corrió.
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Secreto guardado; si no hay, siembra el de fábrica y lo devuelve.
  Future<String> ensureSecret() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(secretKey)))
        .getSingleOrNull();
    final saved = row?.value.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: secretKey, value: defaultSecret));
    return defaultSecret;
  }

  /// Publica en cuanto se calme el movimiento. Es lo que hace que la tienda web
  /// sea el reflejo del catálogo sin que nadie apriete nada.
  void publishSoon() {
    if (!_supabaseReady()) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(_publishQuiet()));
  }

  /// Publica sin lanzar: esto corre en segundo plano y no debe estorbar.
  Future<void> _publishQuiet() async {
    if (_publishing) return;
    _publishing = true;
    try {
      await publish(await ensureSecret());
      lastPublishedAt = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = '$e';
    } finally {
      _publishing = false;
    }
  }

  /// Publica ya, sin esperar el retraso. La usa el botón Compartir.
  Future<void> publishNow() {
    _timer?.cancel();
    return _publishQuiet();
  }

  /// Clave y valor por defecto de la dirección de la tienda en línea.
  static const storeUrlKey = 'catalog_store_url';
  static const defaultStoreUrl = 'https://shelby-caps.pages.dev';

  /// Dirección de la tienda para compartir. Configurable por si algún día se
  /// pone dominio propio.
  Future<String> storeUrl() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(storeUrlKey)))
        .getSingleOrNull();
    final saved = row?.value.trim();
    return (saved == null || saved.isEmpty) ? defaultStoreUrl : saved;
  }

  void dispose() => _timer?.cancel();

  /// Parte PURA (testeable): arma el snapshot desde datos ya leídos.
  static CatalogSnapshot buildSnapshot({
    required List<Product> products,
    required Map<int, String> categoryNames,
    required List<({Variant variant, int stock})> variants,
    required List<PriceTier> tiers,
  }) {
    final byId = {for (final p in products) p.id: p};
    final productIds = byId.keys.toSet();

    final productsJson = [
      for (final p in products)
        {
          'id': p.id,
          'name': p.name,
          'brand': p.brand,
          'category': categoryNames[p.categoryId],
          // La tienda muestra la descripción bajo el nombre ("Gorra negra de
          // malla con visera curva"), igual que el catálogo que ya usa el cliente.
          'description': p.description,
          'base_price_cents': p.basePriceCents,
          'tax_rate_bps': p.taxRateBps,
          'active': p.active,
        }
    ];

    final variantsJson = [
      for (final v in variants)
        if (productIds.contains(v.variant.productId))
          {
            'id': v.variant.id,
            'product_id': v.variant.productId,
            'sku': v.variant.sku,
            'size': v.variant.size,
            'color': v.variant.color,
            'price_cents': effectivePrice(byId[v.variant.productId]!, v.variant),
            'stock': v.stock,
            'active': v.variant.active,
          }
    ];

    final tiersJson = [
      for (final t in tiers)
        if (productIds.contains(t.productId))
          {
            'product_id': t.productId,
            'min_qty': t.minQty,
            'price_cents': t.priceCents,
          }
    ];

    return CatalogSnapshot(productsJson, variantsJson, tiersJson);
  }

  /// Lee el catálogo local (productos activos, variantes activas con existencia
  /// y escalones de mayoreo) y arma el snapshot.
  Future<CatalogSnapshot> currentSnapshot() async {
    final products = await (_db.select(_db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    final cats = {
      for (final c in await _db.select(_db.categories).get()) c.id: c.name
    };
    final variantsRaw = await (_db.select(_db.variants)
          ..where((t) => t.active.equals(true)))
        .get();
    final variants = <({Variant variant, int stock})>[];
    for (final v in variantsRaw) {
      final stock = (await _db.stockFor(v.id)).available;
      variants.add((variant: v, stock: stock));
    }
    final tiers = await _db.select(_db.priceTiers).get();
    return buildSnapshot(
      products: products,
      categoryNames: cats,
      variants: variants,
      tiers: tiers,
    );
  }

  /// Sube las fotos de los productos al bucket público `catalog` y devuelve la
  /// lista lista para publicar (`product_id`, `url`, `position`).
  ///
  /// Por qué hay que subirlas: el POS guarda las fotos como **archivos locales**
  /// de la tablet, y la tienda web no puede leer esas rutas. La posición 0 es la
  /// portada. Se sobrescribe siempre la misma ruta remota (`upsert`), así que
  /// republicar no llena el bucket de basura.
  ///
  /// Las fotos de asset (catálogo de demo) se omiten: no son archivos del
  /// dispositivo. Si una foto falla al subir, se salta y el resto continúa —
  /// más vale publicar el catálogo sin una foto que no publicarlo.
  Future<List<Map<String, dynamic>>> _uploadImages(
      List<Product> products, void Function(int done, int total)? onProgress) async {
    final repo = CatalogRepository(_db);
    final storage = _client.storage.from('catalog');
    final out = <Map<String, dynamic>>[];

    // Se recolecta primero para poder informar avance con un total real.
    final work = <({int productId, int position, String path})>[];
    for (final p in products) {
      final paths = await repo.allImagesOf(p.id);
      for (var i = 0; i < paths.length; i++) {
        if (ImageService.isAsset(paths[i])) continue;
        work.add((productId: p.id, position: i, path: paths[i]));
      }
    }

    var done = 0;
    for (final item in work) {
      try {
        // Archivo en la tablet o data URL en el navegador: `bytesOf` resuelve
        // las dos, así que publicar funciona igual desde la web.
        final bytes = await ImageService.bytesOf(item.path);
        if (bytes != null) {
          final remote = 'p${item.productId}/${item.position}.jpg';
          await storage.uploadBinary(
            remote,
            bytes,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );
          out.add({
            'product_id': item.productId,
            'url': storage.getPublicUrl(remote),
            'position': item.position,
          });
        }
      } catch (_) {
        // Foto que no subió: el producto se publica sin ella.
      }
      onProgress?.call(++done, work.length);
    }
    return out;
  }

  /// Sube las imágenes de los anuncios (portada y banners) y devuelve la lista
  /// lista para publicar. Misma mecánica que las fotos de producto: la ruta
  /// remota es fija por anuncio, así que republicar sobrescribe en vez de
  /// acumular basura en el bucket.
  Future<List<Map<String, dynamic>>> _uploadBanners() async {
    final repo = BannerRepository(_db);
    final storage = _client.storage.from('catalog');
    final out = <Map<String, dynamic>>[];
    final list = await repo.published();

    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      try {
        final bytes = await ImageService.bytesOf(b.path);
        if (bytes == null) continue;
        final remote = 'banners/b${b.id}.jpg';
        await storage.uploadBinary(
          remote,
          bytes,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
        out.add({
          'url': storage.getPublicUrl(remote),
          'caption': b.caption,
          'link': b.link,
          'position': i,
          'is_cover': b.isCover,
        });
      } catch (_) {
        // Un anuncio que no subió no debe tumbar la publicación del catálogo.
      }
    }
    return out;
  }

  /// Publica el snapshot actual. Devuelve cuántos productos se publicaron.
  /// Lanza si Supabase no está configurado o el secreto es inválido.
  ///
  /// [onProgress] informa el avance de la subida de fotos, que es la parte
  /// lenta cuando hay muchos productos con varias vistas cada uno.
  Future<int> publish(String secret,
      {void Function(int done, int total)? onProgress}) async {
    final snap = await currentSnapshot();
    final products = await (_db.select(_db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    final images = await _uploadImages(products, onProgress);
    final banners = await _uploadBanners();
    await _client.rpc('publish_catalog', params: {
      'p_secret': secret,
      'p_products': snap.products,
      'p_variants': snap.variants,
      'p_tiers': snap.tiers,
      'p_images': images,
      'p_banners': banners,
    });
    return snap.productCount;
  }
}
