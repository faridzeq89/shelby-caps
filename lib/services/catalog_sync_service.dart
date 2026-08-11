import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import '../data/repositories/catalog_repository.dart';

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

  /// Publica el snapshot actual. Devuelve cuántos productos se publicaron.
  /// Lanza si Supabase no está configurado o el secreto es inválido.
  Future<int> publish(String secret) async {
    final snap = await currentSnapshot();
    await _client.rpc('publish_catalog', params: {
      'p_secret': secret,
      'p_products': snap.products,
      'p_variants': snap.variants,
      'p_tiers': snap.tiers,
    });
    return snap.productCount;
  }
}
