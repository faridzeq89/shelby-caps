import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/features/catalog/label_service.dart';

void main() {
  late AppDatabase db;
  late CatalogRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CatalogRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> admin() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Admin', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test(
      'Aceptación Fase 3: producto de 12 variantes; cada código resuelve a su variante',
      () async {
    final actor = await admin();
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final catId = await repo.createCategory(actor, 'Blusas');
    final productId = await repo.createProduct(actor,
        name: 'Blusa demo', categoryId: catId, basePriceCents: 24900);

    final created = await repo.generateVariantMatrix(
      actor,
      productId: productId,
      sizes: ['CH', 'M', 'G', 'XG'],
      colors: ['Blanco', 'Negro', 'Rosa'],
      initialStock: 5,
      locationId: locId,
    );

    // 4 tallas × 3 colores = 12 variantes.
    expect(created, hasLength(12));

    // Cada una tiene código interno y stock 5; el código resuelve a ELLA.
    for (final variantId in created) {
      final codes = await repo.barcodesOf(variantId);
      expect(codes, hasLength(1));
      final resolved = await repo.resolveByCode(codes.first.code);
      expect(resolved?.id, variantId);

      final stock = await db.stockFor(variantId);
      expect(stock.available, 5);
    }
  });

  test('no duplica variantes ya existentes al regenerar la matriz', () async {
    final actor = await admin();
    final catId = await repo.createCategory(actor, 'Cat');
    final productId = await repo.createProduct(actor,
        name: 'Prod', categoryId: catId, basePriceCents: 10000);

    await repo.generateVariantMatrix(actor,
        productId: productId, sizes: ['CH', 'M'], colors: ['Negro']);
    final second = await repo.generateVariantMatrix(actor,
        productId: productId, sizes: ['CH', 'M', 'G'], colors: ['Negro']);

    // Solo la talla nueva (G) se crea; CH y M ya existían.
    expect(second, hasLength(1));
    expect((await repo.variantsOf(productId)), hasLength(3));
  });

  test('genera SKUs únicos con colores parecidos (regresión del bug 2067)',
      () async {
    final actor = await admin();
    final catId = await repo.createCategory(actor, 'Playeras');
    final productId = await repo.createProduct(actor,
        name: 'Playera Deportiva', categoryId: catId, basePriceCents: 120000);

    // "Blanco" y "Blanca" recortados a 3 letras daban ambos "BLA" y chocaban.
    final created = await repo.generateVariantMatrix(
      actor,
      productId: productId,
      sizes: ['CH', 'M', 'G', 'XG'],
      colors: ['Blanco', 'Blanca', 'Azul cielo'],
    );
    expect(created, hasLength(12));

    final skus = <String>{};
    for (final id in created) {
      final v =
          await (db.select(db.variants)..where((t) => t.id.equals(id)))
              .getSingle();
      skus.add(v.sku);
    }
    expect(skus, hasLength(12)); // todos distintos, sin colisión
  });

  test('deduplica tallas y colores repetidos en el lote', () async {
    final actor = await admin();
    final catId = await repo.createCategory(actor, 'Cat');
    final productId = await repo.createProduct(actor,
        name: 'Prod', categoryId: catId, basePriceCents: 10000);

    final created = await repo.generateVariantMatrix(
      actor,
      productId: productId,
      sizes: ['M', 'M', ' m '],
      colors: ['Rosa', 'rosa', ' Rosa '],
    );
    expect(created, hasLength(1)); // una sola combinación real
  });

  test('el código de proveedor y el interno resuelven a la misma variante',
      () async {
    final actor = await admin();
    final catId = await repo.createCategory(actor, 'Cat');
    final productId = await repo.createProduct(actor,
        name: 'Prod', categoryId: catId, basePriceCents: 10000);
    final ids = await repo.generateVariantMatrix(actor,
        productId: productId, sizes: ['M'], colors: ['Azul']);
    final variantId = ids.single;

    await repo.addSupplierBarcode(actor, variantId, '7501099012345');

    final internal = (await repo.barcodesOf(variantId))
        .firstWhere((b) => b.source == BarcodeSource.internal);
    expect((await repo.resolveByCode(internal.code))?.id, variantId);
    expect((await repo.resolveByCode('7501099012345'))?.id, variantId);
  });

  test('la hoja de etiquetas PDF se genera sin error', () async {
    final labels = [
      const LabelData(
          productName: 'Blusa', code: 'MB0000000001', priceCents: 24900,
          size: 'M', color: 'Rosa'),
    ];
    final bytes = await LabelService.buildSheetPdf(labels);
    expect(bytes.lengthInBytes, greaterThan(0));

    final zpl = LabelService.buildZpl(labels);
    expect(zpl, contains('^XA'));
    expect(zpl, contains('MB0000000001'));
  });
}
