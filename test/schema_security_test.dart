import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/money.dart';
import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/inventory_repository.dart';
import 'package:pos_boutique/data/seed.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Crea ubicación + categoría + producto + variante y devuelve (locId, varId).
  Future<(int, int)> makeVariant() async {
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'Loc'));
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'Cat'));
    final prodId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Prod',
            categoryId: catId,
            basePriceCents: 10000,
          ),
        );
    final varId = await db.into(db.variants).insert(
          VariantsCompanion.insert(productId: prodId, sku: 'SKU-1'),
        );
    return (locId, varId);
  }

  Future<Profile> makeUser(UserRole role) async {
    final id = await db.insertProfile(
      ProfilesCompanion.insert(
        name: role.name,
        role: role,
        pinSalt: 's',
        pinHash: 'h',
      ),
    );
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('el ledger es append-only: no se puede actualizar ni borrar', () async {
    final (locId, varId) = await makeVariant();
    final inv = InventoryRepository(db);
    await inv.record(
      variantId: varId,
      locationId: locId,
      qty: 5,
      type: MovementType.receipt,
    );

    expect(
      () => db.delete(db.inventoryMovements).go(),
      throwsA(anything),
    );
    expect(
      () => db
          .update(db.inventoryMovements)
          .write(const InventoryMovementsCompanion(reason: Value('x'))),
      throwsA(anything),
    );
  });

  test('available refleja una reserva: on_hand 5, reserved 2, available 3',
      () async {
    final (locId, varId) = await makeVariant();
    final inv = InventoryRepository(db);
    await inv.record(
        variantId: varId, locationId: locId, qty: 5, type: MovementType.receipt);
    await inv.record(
        variantId: varId, locationId: locId, qty: 2, type: MovementType.reserve);

    final stock = await inv.stockFor(varId);
    expect(stock.onHand, 5);
    expect(stock.reserved, 2);
    expect(stock.available, 3);
  });

  test('un cajero no puede editar precios; un admin sí y queda en audit_log',
      () async {
    final (_, varId) = await makeVariant();
    final catalog = CatalogRepository(db);
    final cashier = await makeUser(UserRole.cashier);
    final admin = await makeUser(UserRole.admin);

    await expectLater(
      catalog.updateVariantPrice(
          actor: cashier, variantId: varId, newPriceCents: 9999),
      throwsA(isA<PermissionException>()),
    );

    await catalog.updateVariantPrice(
        actor: admin, variantId: varId, newPriceCents: 12345);

    final variant =
        await (db.select(db.variants)..where((t) => t.id.equals(varId)))
            .getSingle();
    expect(variant.priceCentsOverride, 12345);

    final audits = await db.select(db.auditLog).get();
    expect(audits.where((a) => a.action == 'update_price'), hasLength(1));
  });

  test('folios consecutivos con prefijo de dispositivo', () async {
    expect(await db.nextFolio('T1'), 'T1-000001');
    expect(await db.nextFolio('T1'), 'T1-000002');
    expect(await db.nextFolio('T2'), 'T2-000001');
  });

  test('IVA incluido se desglosa hacia atrás (redondeo a nivel del monto)', () {
    final exact = taxIncludedBreakdown(11600, 1600);
    expect(exact.baseCents, 10000);
    expect(exact.taxCents, 1600);

    final rounded = taxIncludedBreakdown(10000, 1600);
    expect(rounded.baseCents + rounded.taxCents, 10000); // sin centavos perdidos
  });

  test('la semilla base crea sucursal y prefijo, con catálogo VACÍO', () async {
    await SeedService(db).run();

    // Sucursal y prefijo de folios quedan listos.
    final locations = await db.select(db.locations).get();
    expect(locations, isNotEmpty);
    final prefix = await (db.select(db.appSettings)
          ..where((t) => t.key.equals('device_prefix')))
        .getSingleOrNull();
    expect(prefix?.value, SeedService.defaultDevicePrefix);

    // Ya NO se siembra catálogo de ejemplo: arranca vacío.
    final products = await db.select(db.products).get();
    expect(products, isEmpty);
  });
}
