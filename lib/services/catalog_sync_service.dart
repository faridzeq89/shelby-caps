import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../data/repositories/banner_repository.dart';
import '../data/repositories/catalog_repository.dart';
import 'image_service.dart';

/// El catálogo listo para publicar, ya como JSON (listas de mapas) que la
/// función `publish_catalog` de Supabase espera.
class CatalogSnapshot {
  const CatalogSnapshot(this.products, this.variants, this.tiers,
      [this.categories = const []]);
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> tiers;

  /// Las categorías con **el orden que eligió el dueño** (`position`) y si están
  /// archivadas. Sin esto la tienda solo podía acomodarlas alfabéticamente,
  /// porque las deducía de los productos publicados.
  final List<Map<String, dynamic>> categories;
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

  /// ¿Este equipo puede publicar la tienda? **Por dispositivo**, no compartido.
  ///
  /// La tienda no acumula: cada publicación reemplaza el catálogo completo, así
  /// que el último que publica gana. Con dos POS (el del dueño y el de soporte)
  /// bastaba con editar algo en el equivocado para borrarle el catálogo al otro
  /// —pasó el 19 ago 2026—. Apagando esto, ese equipo deja de publicar.
  static const publishEnabledKey = 'catalog_publish_enabled';

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
  /// **En web es corta a propósito.** El POS web corre en Safari, donde los
  /// `Timer` se congelan al cambiar de pestaña o bloquear el teléfono: con 20 s,
  /// el dueño archivaba algo, salía de la pestaña y la publicación nunca corría
  /// —la tienda se quedaba mostrando el catálogo viejo—. Tres segundos siguen
  /// juntando una ráfaga de ediciones sin dar tiempo a perderse.
  static const _debounce = Duration(seconds: kIsWeb ? 3 : 20);

  Timer? _timer;
  bool _publishing = false;

  /// Llegó un cambio mientras se publicaba: hay que volver a publicar al
  /// terminar. Sin esto, el último cambio de una ráfaga se quedaba sin subir.
  bool _dirty = false;

  /// La función `publish_catalog` de este proyecto todavía no acepta categorías
  /// (falta correr `0007_catalog_categories.sql`). Lo muestra la pantalla de
  /// categorías para que el dueño sepa por qué el orden no llega a la tienda.
  bool categoriesUnsupported = false;

  /// Último resultado, para que la pantalla de catálogo pueda mostrarlo.
  DateTime? lastPublishedAt;
  String? lastError;

  /// En qué paso va (o murió) la publicación. Sin esto, un fallo se veía como
  /// "Load failed" pelón y no se sabía si tronó leyendo el catálogo, subiendo
  /// fotos o mandando el snapshot — que es exactamente lo que costó una tarde
  /// el 20 ago 2026.
  String? lastStep;

  /// Diagnóstico de la última publicación de banners (para depurar en web).
  int dbgBannersFound = 0;
  int dbgBannersUploaded = 0;
  String? dbgBannerNote;

  /// Fotos subidas y saltadas en la última publicación. Con el catálogo
  /// cargado, lo normal es 0 subidas: si aquí sale un número grande cada vez,
  /// algo está invalidando las huellas y la publicación volvió a ser de megas.
  int dbgImagesUploaded = 0;
  int dbgImagesSkipped = 0;

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

  /// ¿Este equipo publica? De fábrica **sí**: apagarlo es una decisión, y un
  /// dispositivo recién instalado no tiene por qué quedarse mudo.
  Future<bool> publishEnabled() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(publishEnabledKey)))
        .getSingleOrNull();
    return row?.value.trim() != 'false';
  }

  Future<void> setPublishEnabled(bool value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
            key: publishEnabledKey, value: value ? 'true' : 'false'));
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
    if (_publishing) {
      // Publicar tarda (sube fotos). Lo que llegó mientras tanto no se tira: se
      // apunta y se publica en cuanto termine la vuelta actual.
      _dirty = true;
      return;
    }
    _publishing = true;
    try {
      await publish(await ensureSecret());
      lastPublishedAt = DateTime.now();
      lastError = null;
    } catch (e) {
      lastError = '[${lastStep ?? 'inicio'}] $e';
    } finally {
      _publishing = false;
    }
    if (_dirty) {
      _dirty = false;
      await _publishQuiet();
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
    List<Category> categories = const [],
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

    // Se publican TODAS, archivadas incluidas, con su bandera: la tienda necesita
    // saber que una categoría existe pero está archivada para NO ponerle botón,
    // aunque algún producto siga apuntando a ella. Si solo se mandaran las
    // activas, la tienda no distinguiría "archivada" de "categoría publicada por
    // un POS más viejo" y la volvería a mostrar.
    final categoriesJson = [
      for (var i = 0; i < categories.length; i++)
        {
          'name': categories[i].name,
          'position': i,
          'active': categories[i].active,
        }
    ];

    return CatalogSnapshot(
        productsJson, variantsJson, tiersJson, categoriesJson);
  }

  /// Lee el catálogo local (productos activos, variantes activas con existencia
  /// y escalones de mayoreo) y arma el snapshot.
  Future<CatalogSnapshot> currentSnapshot() async {
    final products = await (_db.select(_db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    // En el orden del dueño: es el orden con el que salen en la tienda.
    final catRows = await CatalogRepository(_db).categories();
    final cats = {for (final c in catRows) c.id: c.name};
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
      categories: catRows,
    );
  }

  /// Huella de lo ya subido: `"p12/0"` → sha1 de los bytes. Vive en una sola
  /// fila de `app_settings` (no una por foto) para no llenar la tabla.
  static const uploadedImagesKey = 'catalog_images_uploaded';

  Future<Map<String, String>> _uploadedFingerprints() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(uploadedImagesKey)))
        .getSingleOrNull();
    if (row == null || row.value.trim().isEmpty) return {};
    try {
      final m = jsonDecode(row.value) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: '${e.value}'};
    } catch (_) {
      // Fila corrupta: se trata como si no hubiera nada subido. Publicar de más
      // es lento; publicar de menos deja la tienda sin fotos.
      return {};
    }
  }

  Future<void> _saveFingerprints(Map<String, String> huellas) =>
      _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
              key: uploadedImagesKey, value: jsonEncode(huellas)));

  /// Sube las fotos de los productos al bucket público `catalog` y devuelve la
  /// lista lista para publicar (`product_id`, `url`, `position`).
  ///
  /// **Solo sube las que cambiaron.** Antes re-subía TODAS en cada publicación
  /// (`upsert` a ciegas): con 74 fotos son ~8 MB por cada cambio de precio, y
  /// desde un teléfono eso hacía que la publicación muriera antes de llegar al
  /// último paso —el RPC— con "Load failed" (reportado el 20 ago 2026). La
  /// huella es el sha1 de los bytes: si es la misma, el archivo remoto ya está
  /// y solo se manda su URL.
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

    final huellas = await _uploadedFingerprints();
    final vigentes = <String, String>{};
    dbgImagesUploaded = 0;
    dbgImagesSkipped = 0;

    var done = 0;
    for (final item in work) {
      try {
        // Archivo en la tablet o data URL en el navegador: `bytesOf` resuelve
        // las dos, así que publicar funciona igual desde la web.
        final bytes = await ImageService.bytesOf(item.path);
        if (bytes != null) {
          final remote = 'p${item.productId}/${item.position}.jpg';
          final huella = sha1.convert(bytes).toString();
          if (huellas[remote] == huella) {
            // Ya está allá arriba, idéntica: no se vuelve a mandar.
            dbgImagesSkipped++;
          } else {
            await storage.uploadBinary(
              remote,
              bytes,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
            dbgImagesUploaded++;
          }
          // La huella se guarda SOLO si la foto quedó arriba (subida ahora o
          // desde antes). Si la subida truena, no se apunta y se reintenta a la
          // próxima.
          vigentes[remote] = huella;
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
    await _saveFingerprints(vigentes);
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
    dbgBannersFound = list.length;
    dbgBannerNote = null;

    for (var i = 0; i < list.length; i++) {
      final b = list[i];
      try {
        final bytes = await ImageService.bytesOf(b.path);
        if (bytes == null) {
          final head = b.path.length <= 22 ? b.path : b.path.substring(0, 22);
          dbgBannerNote = 'sin bytes (${b.path.length} car., "$head…")';
          continue;
        }
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
      } catch (e) {
        // Un anuncio que no subió no debe tumbar la publicación del catálogo.
        dbgBannerNote = 'error al subir: $e';
      }
    }
    dbgBannersUploaded = out.length;
    return out;
  }

  /// Publica el snapshot actual. Devuelve cuántos productos se publicaron.
  /// Lanza si Supabase no está configurado o el secreto es inválido.
  ///
  /// [onProgress] informa el avance de la subida de fotos, que es la parte
  /// lenta cuando hay muchos productos con varias vistas cada uno.
  Future<int> publish(String secret,
      {void Function(int done, int total)? onProgress}) async {
    // Candado en el ÚNICO punto que toca el RPC: cualquier ruta de publicación
    // —automática, botón Compartir, anuncios— pasa por aquí, así ninguna nueva
    // se lo salta por olvido.
    if (!await publishEnabled()) throw const PublishDisabledException();
    lastStep = 'leyendo el catálogo';
    final snap = await currentSnapshot();
    final products = await (_db.select(_db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    lastStep = 'fotos';
    final images = await _uploadImages(products, onProgress);
    lastStep = 'fotos: $dbgImagesUploaded subidas, $dbgImagesSkipped ya estaban';
    final banners = await _uploadBanners();
    lastStep = 'anuncios listos, mandando ${snap.productCount} productos';
    final params = {
      'p_secret': secret,
      'p_products': snap.products,
      'p_variants': snap.variants,
      'p_tiers': snap.tiers,
      'p_images': images,
      'p_banners': banners,
    };
    try {
      await _client.rpc('publish_catalog', params: {
        ...params,
        'p_categories': snap.categories,
      });
      categoriesUnsupported = false;
    } on PostgrestException catch (e) {
      // La firma con categorías la agrega `0007_catalog_categories.sql`. Si ese
      // script todavía no se corrió en Supabase, PostgREST responde "no existe
      // esa función" (PGRST202): se publica con la firma anterior en vez de
      // dejar la tienda sin actualizar. Lo único que se pierde es el orden
      // manual de las categorías.
      if (e.code != 'PGRST202' && !e.message.contains('does not exist')) {
        rethrow;
      }
      categoriesUnsupported = true;
      await _client.rpc('publish_catalog', params: params);
    }
    lastStep = 'listo';
    return snap.productCount;
  }
}

/// Este equipo tiene apagada la publicación de la tienda.
///
/// No es un fallo: es la protección para que un POS de respaldo no reemplace el
/// catálogo del dueño. Se prende en Ajustes → Publicación de la tienda.
class PublishDisabledException implements Exception {
  const PublishDisabledException();

  @override
  String toString() =>
      'Este equipo no publica la tienda (Ajustes → Publicación de la tienda).';
}
