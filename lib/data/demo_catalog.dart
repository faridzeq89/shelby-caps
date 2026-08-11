import 'package:drift/drift.dart';
import 'package:image/image.dart' as img;

import '../services/image_service.dart';
import 'local/database.dart';
import 'repositories/catalog_repository.dart';

/// Una gorra del catálogo de prueba.
class _Cap {
  const _Cap(this.name, this.category, this.priceCents, this.stock, this.base,
      this.accent, this.label,
      {this.description, this.wholesale = false});
  final String name;
  final String category;
  final int priceCents;
  final int stock;
  final int base; // color principal (0xRRGGBB)
  final int accent; // color del acento
  final String label; // texto corto de la foto
  final String? description;
  final bool wholesale;
}

/// Carga un **catálogo de prueba** de gorras: mismos nombres, precios y
/// agotados que el catálogo real del cliente, con fotos generadas aquí mismo
/// (varias vistas por modelo) y escalones de mayoreo.
///
/// Sirve para dos cosas a la vez: llenar el POS para poder probarlo, y que al
/// publicar, la **tienda web muestre exactamente lo mismo**. No se carga sola:
/// el dueño la pide desde Admin, y se puede quitar igual de fácil.
class DemoCatalogService {
  DemoCatalogService(this._db);
  final AppDatabase _db;

  static const _caps = <_Cap>[
    _Cap('17 OHTANI', 'New Era G5', 60000, 6, 0x1B2A4A, 0xC8A24A, '17',
        wholesale: true),
    _Cap('3 CRUCES / PERSONALIZADA', 'Personalizado', 70000, 3, 0x111111,
        0xE8E8E8, '3C'),
    _Cap('ADIDAS', 'Réplica Premium', 70000, 4, 0xC8B28A, 0x5A4632, 'AD',
        description: 'Gorra beige y cafe de tela con visera curva',
        wholesale: true),
    _Cap('ADIDAS BLACK', 'Réplica Premium', 70000, 5, 0x141414, 0xFFFFFF, 'AD',
        description: 'Gorra negra de tela con logo blanco y visera curva',
        wholesale: true),
    _Cap('ALO AZUL CLARO', 'Originales', 85000, 2, 0x7FB3D5, 0xFFFFFF, 'alo'),
    _Cap('ALO AZUL MARINO', 'Originales', 85000, 0, 0x1F3864, 0xFFFFFF, 'alo'),
    _Cap('ALO BLANCA', 'Originales', 85000, 3, 0xF2F2F2, 0x333333, 'alo',
        description: 'Gorra blanca malla trasera visera curva'),
    _Cap('ALO NEGRA', 'Originales', 85000, 4, 0x141414, 0xFFFFFF, 'alo',
        description: 'Gorra negra de malla con visera curva'),
    _Cap('AMIRI CRYSTAL GAMUZA', 'Réplica Premium', 95000, 0, 0x6B5B73,
        0xE6D7F2, 'AM'),
    _Cap('AMIRI GREY / BIGGBOSS', 'Réplica Premium', 95000, 0, 0x8A8A8A,
        0x222222, 'AM'),
    _Cap('ANGELS NEGRA', 'New Era G5', 60000, 7, 0x141414, 0xC8102E, 'A',
        wholesale: true),
    _Cap('ASTROS NARANJA/NEGRO', 'New Era G5', 60000, 5, 0xEB6E1F, 0x0F1E2E,
        'H', wholesale: true),
    _Cap('ATLANTA', 'New Era G5', 60000, 4, 0x13274F, 0xCE1141, 'A',
        wholesale: true),
    _Cap('BILLS', 'New Era G5', 60000, 6, 0x00338D, 0xC60C30, 'B',
        wholesale: true),
    _Cap('BOSS', 'Réplica Premium', 70000, 0, 0x141414, 0xFFFFFF, 'BOSS',
        description: 'Gorra negra de tela, visera curva, logo BOSS al frente'),
    _Cap('BOSTON CAPS FANS', 'Personalizado', 130000, 2, 0x141414, 0xD6B25E,
        'B',
        description:
            'Gorra negra de tela con aplique brillante y visera curva'),
    _Cap('BOSTON ROJA CORAZÓN', 'Personalizado', 130000, 0, 0xBD3039, 0xFFFFFF,
        'B'),
    _Cap('BULLS AZUL', 'New Era G5', 60000, 5, 0x1D428A, 0xCE1141, 'B',
        wholesale: true),
    _Cap('BY CHAVALON', 'Personalizado', 150000, 2, 0x141414, 0xC8A24A, 'CH',
        description: 'Gorra negra de tela con visera curva y bordado'),
    _Cap('DODGERS AZUL', 'New Era G5', 60000, 8, 0x005A9C, 0xFFFFFF, 'LA',
        wholesale: true),
    _Cap('LLAVERO GORRA', 'Accesorios', 12000, 20, 0x8A6D3B, 0xF0E6D2, 'LL'),
    _Cap('NY YANKEES NEGRA', 'New Era G5', 60000, 9, 0x0C2340, 0xFFFFFF, 'NY',
        wholesale: true),
    _Cap('RAIDERS NEGRA', 'New Era G5', 60000, 6, 0x0B0B0B, 0xA5ACAF, 'R',
        wholesale: true),
    _Cap('TEXAS AZUL MARINO', 'New Era G5', 60000, 0, 0x003278, 0xC0111F, 'T'),
  ];

  /// ¿Ya hay productos? Se usa para avisar antes de duplicar.
  Future<bool> hasProducts() async {
    final rows = await _db.select(_db.products).get();
    return rows.isNotEmpty;
  }

  /// Carga el catálogo de prueba. Devuelve cuántos productos creó.
  Future<int> load(Profile actor) async {
    final repo = CatalogRepository(_db);
    final images = ImageService();
    final locationId =
        (await _db.select(_db.locations).getSingleOrNull())?.id;

    // Categorías existentes por nombre, para no duplicarlas.
    final cats = <String, int>{
      for (final c in await _db.select(_db.categories).get()) c.name: c.id,
    };

    var created = 0;
    for (final cap in _caps) {
      final categoryId =
          cats[cap.category] ??= await repo.createCategory(actor, cap.category);

      final productId = await repo.createProduct(
        actor,
        name: cap.name,
        categoryId: categoryId,
        basePriceCents: cap.priceCents,
        brand: cap.category == 'Accesorios' ? null : 'Shelby',
        description: cap.description,
      );

      // Las gorras son de talla única: una variante por modelo.
      final variantId = await _db.into(_db.variants).insert(
            VariantsCompanion.insert(
              productId: productId,
              sku: 'SC-${productId.toString().padLeft(4, '0')}',
              costCents: Value((cap.priceCents * 0.45).round()),
            ),
          );
      await _db.into(_db.barcodes).insert(
            BarcodesCompanion.insert(
              variantId: variantId,
              code: 'MB${(900000 + productId).toString().padLeft(10, '0')}',
              source: BarcodeSource.internal,
            ),
          );
      if (cap.stock > 0 && locationId != null) {
        await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                variantId: variantId,
                locationId: locationId,
                qty: cap.stock,
                type: MovementType.receipt,
                userId: Value(actor.id),
                reason: const Value('Catálogo de prueba'),
              ),
            );
      }

      if (cap.wholesale) {
        await repo.setPriceTiers(actor: actor, productId: productId, tiers: [
          (minQty: 6, priceCents: (cap.priceCents * 0.85).round()),
          (minQty: 12, priceCents: (cap.priceCents * 0.75).round()),
        ]);
      }

      // Varias vistas por gorra: es justo lo que el cliente pidió poder subir.
      final vistas = cap.category == 'Accesorios'
          ? ['detalle']
          : ['frente', 'perfil', 'atras', 'detalle'];
      for (final vista in vistas) {
        final bytes = _capPhoto(cap, vista);
        final path = await images.saveOptimizedBytes(bytes);
        if (path != null) {
          await repo.addProductImage(
              actor: actor, productId: productId, path: path);
        }
      }
      created++;
    }
    return created;
  }

  /// Retira el catálogo de la vista: deja las existencias en cero con un
  /// movimiento de ajuste, borra las fotos y el mayoreo, y **archiva** los
  /// productos.
  ///
  /// No borra filas de producto ni de inventario a propósito:
  /// `inventory_movements` es un **libro mayor append-only** (hay un trigger que
  /// lo impide), y las variantes lo referencian. Archivar es la forma correcta
  /// de sacar mercancía de circulación sin falsear el historial.
  ///
  /// Devuelve cuántos productos archivó.
  Future<int> retire(Profile actor) async {
    final images = ImageService();
    final repo = CatalogRepository(_db);
    final all = await (_db.select(_db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    final locationId =
        (await _db.select(_db.locations).getSingleOrNull())?.id;

    for (final p in all) {
      // 1) Existencias a cero con un ajuste (no se borra el movimiento viejo).
      if (locationId != null) {
        for (final v in await repo.variantsOf(p.id)) {
          final stock = (await _db.stockFor(v.id)).available;
          if (stock != 0) {
            await _db.into(_db.inventoryMovements).insert(
                  InventoryMovementsCompanion.insert(
                    variantId: v.id,
                    locationId: locationId,
                    qty: -stock,
                    type: MovementType.adjustment,
                    userId: Value(actor.id),
                    reason: const Value('Retiro de catálogo de prueba'),
                  ),
                );
          }
        }
      }

      // 2) Fotos: archivo y fila.
      final gallery = await repo.galleryOf(p.id);
      for (final g in gallery) {
        await images.delete(g.path);
      }
      await images.delete(p.imagePath);
      await (_db.delete(_db.productImages)
            ..where((t) => t.productId.equals(p.id)))
          .go();
      await (_db.update(_db.products)..where((t) => t.id.equals(p.id)))
          .write(const ProductsCompanion(imagePath: Value(null)));

      // 3) Mayoreo y archivado.
      await (_db.delete(_db.priceTiers)
            ..where((t) => t.productId.equals(p.id)))
          .go();
      await (_db.update(_db.products)..where((t) => t.id.equals(p.id)))
          .write(const ProductsCompanion(active: Value(false)));
    }
    return all.length;
  }

  /// Dibuja una "foto" de la gorra. No pretende ser bonita: pretende que cada
  /// vista se distinga de las otras para poder probar la galería.
  static Uint8List _capPhoto(_Cap cap, String vista) {
    const size = 600;
    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(0xF2, 0xF2, 0xF2));

    final base = img.ColorRgb8(
        (cap.base >> 16) & 0xFF, (cap.base >> 8) & 0xFF, cap.base & 0xFF);
    final accent = img.ColorRgb8((cap.accent >> 16) & 0xFF,
        (cap.accent >> 8) & 0xFF, cap.accent & 0xFF);

    switch (vista) {
      case 'frente':
        // Copa (media circunferencia) + visera al frente.
        img.fillCircle(image, x: 300, y: 330, radius: 190, color: base);
        img.fillRect(image, x1: 100, y1: 330, x2: 500, y2: 520,
            color: img.ColorRgb8(0xF2, 0xF2, 0xF2));
        img.fillCircle(image, x: 300, y: 330, radius: 190, color: base);
        img.fillRect(image, x1: 110, y1: 330, x2: 490, y2: 380, color: base);
        img.fillCircle(image, x: 300, y: 385, radius: 120, color: accent);
      case 'perfil':
        img.fillCircle(image, x: 320, y: 330, radius: 170, color: base);
        img.fillRect(image, x1: 320, y1: 330, x2: 560, y2: 375, color: accent);
        img.fillRect(image, x1: 316, y1: 160, x2: 324, y2: 330, color: accent);
      case 'atras':
        img.fillCircle(image, x: 300, y: 320, radius: 180, color: base);
        img.fillRect(image, x1: 240, y1: 300, x2: 360, y2: 380, color: accent);
      default: // detalle
        img.fillCircle(image, x: 300, y: 300, radius: 200, color: base);
        img.fillCircle(image, x: 300, y: 300, radius: 120, color: accent);
    }

    img.drawString(image, cap.label,
        font: img.arial48, x: 40, y: 40, color: base);
    img.drawString(image, vista,
        font: img.arial24,
        x: 40,
        y: 540,
        color: img.ColorRgb8(0x9A, 0x9A, 0x9A));

    return Uint8List.fromList(img.encodeJpg(image, quality: 88));
  }
}
