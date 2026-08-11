import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:pos_boutique/data/demo_catalog.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/services/catalog_sync_service.dart';

/// `path_provider` habla por canal de plataforma, que no existe en un unit
/// test. Este doble lo apunta a una carpeta temporal real, así el sembrado
/// escribe fotos de verdad y la prueba mide lo que de verdad pasa.
class _TmpPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TmpPathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

/// El catálogo de prueba tiene que servir para dos cosas a la vez: llenar el POS
/// y que, al publicar, la tienda web muestre **lo mismo**. Eso es lo que se
/// verifica aquí: que lo sembrado sea exactamente lo que sale en el snapshot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('shelby_demo_');
    PathProviderPlatform.instance = _TmpPathProvider(tmp);
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Profile> admin() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Admin', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('siembra las gorras con categorías, agotados y mayoreo', () async {
    final actor = await admin();
    await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

    final n = await DemoCatalogService(db).load(actor);
    expect(n, 24);

    final products = await db.select(db.products).get();
    expect(products.length, 24);

    // Las categorías del catálogo real del cliente.
    final cats = (await db.select(db.categories).get()).map((c) => c.name).toSet();
    expect(cats, containsAll(<String>{
      'New Era G5',
      'Originales',
      'Personalizado',
      'Réplica Premium',
      'Accesorios',
    }));

    // Hay agotados: la tienda debe poder mostrar "Producto agotado".
    final repo = CatalogRepository(db);
    var sinStock = 0;
    for (final p in products) {
      final vs = await repo.variantsOf(p.id);
      final stock = (await db.stockFor(vs.single.id)).available;
      if (stock == 0) sinStock++;
    }
    expect(sinStock, greaterThan(0));

    // Mayoreo solo en los modelos de línea.
    final tiers = await db.select(db.priceTiers).get();
    expect(tiers, isNotEmpty);
    expect(tiers.every((t) => t.minQty >= 6), isTrue);
  });

  test('cada gorra queda con portada y galería de varias vistas', () async {
    final actor = await admin();
    await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    await DemoCatalogService(db).load(actor);

    final repo = CatalogRepository(db);
    final gorra = await (db.select(db.products)
          ..where((t) => t.name.equals('ALO NEGRA')))
        .getSingle();

    expect(gorra.imagePath, isNotNull, reason: 'debe tener portada');
    final todas = await repo.allImagesOf(gorra.id);
    expect(todas.length, 4, reason: 'frente, perfil, atrás y detalle');
  });

  test('lo sembrado es lo mismo que se publica a la tienda', () async {
    final actor = await admin();
    await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    await DemoCatalogService(db).load(actor);

    final snap = await CatalogSyncService(db).currentSnapshot();
    expect(snap.productCount, 24);

    final boston = snap.products.firstWhere((p) => p['name'] == 'BOSTON CAPS FANS');
    expect(boston['base_price_cents'], 130000);
    expect(boston['category'], 'Personalizado');
    expect(boston['description'],
        'Gorra negra de tela con aplique brillante y visera curva',
        reason: 'la descripción viaja a la tienda, como en el catálogo real');
  });

  test('retirar archiva, deja stock en cero y NO altera el libro mayor',
      () async {
    final actor = await admin();
    await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final demo = DemoCatalogService(db);
    await demo.load(actor);

    final movimientosAntes = (await db.select(db.inventoryMovements).get()).length;
    final n = await demo.retire(actor);
    expect(n, 24);

    // Nada visible queda activo.
    final activos = await (db.select(db.products)
          ..where((t) => t.active.equals(true)))
        .get();
    expect(activos, isEmpty);

    // Las existencias quedan en cero, variante por variante.
    final repo = CatalogRepository(db);
    for (final p in await db.select(db.products).get()) {
      for (final v in await repo.variantsOf(p.id)) {
        expect((await db.stockFor(v.id)).available, 0);
      }
    }

    // El libro mayor solo CRECE: los movimientos viejos siguen ahí.
    final movimientosDespues =
        (await db.select(db.inventoryMovements).get()).length;
    expect(movimientosDespues, greaterThan(movimientosAntes),
        reason: 'el retiro se registra como ajuste, no borrando historial');

    expect(await db.select(db.productImages).get(), isEmpty);
    expect(await db.select(db.priceTiers).get(), isEmpty);
    expect((await db.select(db.locations).get()).length, 1,
        reason: 'la sucursal no es catálogo');
  });
}
