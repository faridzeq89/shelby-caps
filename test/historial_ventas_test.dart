import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';

/// Historial de ventas ("qué se vendió y cuándo") y la cancelación, que el dueño
/// pidió el 20 ago 2026.
///
/// El punto delicado es cancelar: **regresa inventario**. Cancelar dos veces, o
/// cancelar algo que ya se devolvió, o un apartado —que reserva y no descuenta—
/// inventa mercancía que nunca entró. Eso es lo que cuidan estas pruebas.
void main() {
  late AppDatabase db;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'Principal'));

  Future<(Product, Variant)> gorra(int locId,
      {String nombre = 'Gorra negra',
      String talla = 'Única',
      int stock = 10}) async {
    final catId = await db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: 'GORRAS'));
    final pid = await db.into(db.products).insert(ProductsCompanion.insert(
        name: nombre, categoryId: catId, basePriceCents: 70000));
    final vid = await db.into(db.variants).insert(VariantsCompanion.insert(
        productId: pid,
        sku: 'SKU-$nombre',
        size: Value(talla),
        color: const Value('Negro')));
    await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
            variantId: vid,
            locationId: locId,
            qty: stock,
            type: MovementType.receipt));
    final p =
        await (db.select(db.products)..where((t) => t.id.equals(pid))).getSingle();
    final v =
        await (db.select(db.variants)..where((t) => t.id.equals(vid))).getSingle();
    return (p, v);
  }

  Future<CheckoutResult> vender(Profile caja, int locId, Product p, Variant v,
          {int qty = 2}) =>
      sales.checkout(
        cashier: caja,
        locationId: locId,
        lines: [
          CheckoutLine(product: p, variant: v, qty: qty, unitPriceCents: 70000)
        ],
        payments: [PaymentInput(PaymentMethod.cash, 70000 * qty)],
      );

  group('qué se vendió y cuándo', () {
    test('trae las ventas del periodo, la más reciente primero', () async {
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, stock: 20);
      final a = await vender(caja, locId, p, v, qty: 1);
      final b = await vender(caja, locId, p, v, qty: 1);

      final hoy = DateTime.now();
      final desde = DateTime(hoy.year, hoy.month, hoy.day);
      final lista = await sales.history(
          desde: desde, hasta: desde.add(const Duration(days: 1)));

      expect(lista.length, 2);
      expect(lista.first.folio, b.folio, reason: 'la más nueva arriba');
      expect(lista.last.folio, a.folio);
    });

    test('deja fuera lo que no cae en el periodo', () async {
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId);
      await vender(caja, locId, p, v, qty: 1);

      final ayer = DateTime.now().subtract(const Duration(days: 1));
      final lista = await sales.history(
          desde: DateTime(ayer.year, ayer.month, ayer.day),
          hasta: DateTime(ayer.year, ayer.month, ayer.day)
              .add(const Duration(days: 1)));
      expect(lista, isEmpty);
    });

    test('los renglones dicen el producto, la talla y el color', () async {
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, nombre: 'New Era 59', talla: 'M');
      final r = await vender(caja, locId, p, v, qty: 3);

      final lineas = await sales.linesOf(r.saleId);
      expect(lineas.length, 1);
      expect(lineas.single.productName, 'New Era 59');
      expect(lineas.single.qty, 3);
      expect(lineas.single.titulo, 'New Era 59 · M / Negro');
      expect(lineas.single.lineTotalCents, 210000);

      final pagos = await sales.paymentsOf(r.saleId);
      expect(pagos.single.method, PaymentMethod.cash);
      expect(pagos.single.amountCents, 210000);
    });

    test('una venta cancelada SIGUE apareciendo, marcada', () async {
      // Que desaparezca sería peor: el dueño tiene que poder ver que existió.
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId);
      final r = await vender(caja, locId, p, v, qty: 1);
      await sales.cancelSale(actor: admin, saleId: r.saleId);

      final hoy = DateTime.now();
      final desde = DateTime(hoy.year, hoy.month, hoy.day);
      final lista = await sales.history(
          desde: desde, hasta: desde.add(const Duration(days: 1)));
      expect(lista.single.status, SaleStatus.cancelled);
    });
  });

  group('cancelar', () {
    test('regresa el inventario, conserva el folio y queda en la bitácora',
        () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, stock: 10);
      final r = await vender(caja, locId, p, v, qty: 2);

      expect((await db.stockFor(v.id)).onHand, 8);

      await sales.cancelSale(
          actor: admin, saleId: r.saleId, reason: 'venta de prueba');

      final venta = await sales.saleById(r.saleId);
      expect(venta!.status, SaleStatus.cancelled);
      expect(venta.folio, r.folio, reason: 'hay un ticket impreso con ese folio');
      expect((await db.stockFor(v.id)).onHand, 10, reason: 'las piezas vuelven');

      final log = await (db.select(db.auditLog)
            ..where((t) => t.action.equals('cancel_sale')))
          .get();
      expect(log.single.entityId, r.saleId);
      expect(log.single.detail, 'venta de prueba');
    });

    test('cancelar dos veces no regresa el inventario dos veces', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, stock: 10);
      final r = await vender(caja, locId, p, v, qty: 2);

      await sales.cancelSale(actor: admin, saleId: r.saleId);
      await sales.cancelSale(actor: admin, saleId: r.saleId);

      expect((await db.stockFor(v.id)).onHand, 10,
          reason: 'no 12: el segundo intento no hace nada');
    });

    test('un apartado NO se cancela aquí: reserva, no descuenta', () async {
      // Devolver piezas que nunca salieron del inventario lo infla.
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, stock: 10);
      final r = await vender(caja, locId, p, v, qty: 2);
      await (db.update(db.sales)..where((t) => t.id.equals(r.saleId)))
          .write(const SalesCompanion(status: Value(SaleStatus.layaway)));

      await expectLater(sales.cancelSale(actor: admin, saleId: r.saleId),
          throwsA(isA<StateError>()));
      expect((await db.stockFor(v.id)).onHand, 8, reason: 'nada se movió');
    });

    test('una venta ya devuelta NO se cancela', () async {
      final admin = await user(UserRole.admin);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId, stock: 10);
      final r = await vender(caja, locId, p, v, qty: 2);
      await (db.update(db.sales)..where((t) => t.id.equals(r.saleId)))
          .write(const SalesCompanion(status: Value(SaleStatus.returned)));

      await expectLater(sales.cancelSale(actor: admin, saleId: r.saleId),
          throwsA(isA<StateError>()));
      expect((await db.stockFor(v.id)).onHand, 8,
          reason: 'no 10: la devolución ya regresó lo suyo');
    });

    test('el cajero no cancela ventas', () async {
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId);
      final r = await vender(caja, locId, p, v, qty: 1);
      expect(() => sales.cancelSale(actor: caja, saleId: r.saleId),
          throwsA(isA<PermissionException>()));
    });

    test('el gerente sí cancela', () async {
      final gerente = await user(UserRole.manager);
      final caja = await user(UserRole.cashier);
      final locId = await location();
      final (p, v) = await gorra(locId);
      final r = await vender(caja, locId, p, v, qty: 1);
      await sales.cancelSale(actor: gerente, saleId: r.saleId);
      expect((await sales.saleById(r.saleId))!.status, SaleStatus.cancelled);
    });
  });
}
