import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
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

  SupabaseClient get _client => Supabase.instance.client;

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
        final file = File(item.path);
        if (await file.exists()) {
          final remote = 'p${item.productId}/${item.position}.jpg';
          await storage.uploadBinary(
            remote,
            await file.readAsBytes(),
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
    await _client.rpc('publish_catalog', params: {
      'p_secret': secret,
      'p_products': snap.products,
      'p_variants': snap.variants,
      'p_tiers': snap.tiers,
      'p_images': images,
    });
    return snap.productCount;
  }
}
