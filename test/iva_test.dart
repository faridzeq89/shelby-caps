import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';
import 'package:pos_boutique/services/tax_settings.dart';

/// El cliente **no factura**: el IVA no debe aparecer ni guardarse. Queda como
/// interruptor por si algún día factura, así que las dos posiciones importan.
void main() {
  late AppDatabase db;
  late CatalogRepository catalog;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    catalog = CatalogRepository(db);
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> admin() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Admin', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Vende una gorra de $580 (precio con IVA incluido al 16 %).
  Future<CheckoutResult> vender(Profile actor,
      {required bool taxEnabled}) async {
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final cat = await catalog.createCategory(actor, 'Gorras');
    final productId = await catalog.createSimpleProduct(actor,
        name: 'Gorra', categoryId: cat, basePriceCents: 58000,
        initialStock: 5, locationId: locId);
    final product = (await catalog.productById(productId))!;
    final variant = (await catalog.variantsOf(productId)).single;

    return sales.checkout(
      cashier: actor,
      locationId: locId,
      lines: [
        CheckoutLine(
            product: product, variant: variant, qty: 1, unitPriceCents: 58000),
      ],
      payments: [
        const PaymentInput(PaymentMethod.cash, 58000),
      ],
      taxEnabled: taxEnabled,
    );
  }

  test('apagado: la venta se guarda SIN impuesto', () async {
    final actor = await admin();
    final r = await vender(actor, taxEnabled: false);

    final sale = await (db.select(db.sales)..where((t) => t.id.equals(r.saleId)))
        .getSingle();
    expect(sale.taxCents, 0, reason: 'el precio es el precio');
    expect(sale.subtotalCents, 58000,
        reason: 'sin desglose, el subtotal es el total');
    expect(sale.totalCents, 58000);

    final lines = await (db.select(db.saleLines)
          ..where((t) => t.saleId.equals(r.saleId)))
        .get();
    expect(lines.single.taxCents, 0);
  });

  test('prendido: vuelve el desglose con IVA incluido', () async {
    final actor = await admin();
    final r = await vender(actor, taxEnabled: true);

    final sale = await (db.select(db.sales)..where((t) => t.id.equals(r.saleId)))
        .getSingle();
    expect(sale.totalCents, 58000, reason: 'el cliente paga lo mismo');
    expect(sale.taxCents, 8000,
        reason: '58000 con 16% incluido = 50000 base + 8000 de IVA');
    expect(sale.subtotalCents, 50000);
  });

  group('ajuste guardado', () {
    test('de fábrica viene apagado', () async {
      final tax = TaxSettings(db);
      await tax.load();
      expect(tax.enabled, isFalse);
    });

    test('se guarda y sobrevive a reabrir la app', () async {
      final tax = TaxSettings(db);
      await tax.setEnabled(true);

      // Otra instancia = como si la app hubiera arrancado de nuevo.
      final otra = TaxSettings(db);
      await otra.load();
      expect(otra.enabled, isTrue);
    });

    test('rateFor devuelve cero mientras esté apagado', () async {
      final tax = TaxSettings(db);
      await tax.load();
      expect(tax.rateFor(1600), 0);
      await tax.setEnabled(true);
      expect(tax.rateFor(1600), 1600);
    });
  });

  test('el historial NO se reescribe al apagar el IVA', () async {
    final actor = await admin();
    final conIva = await vender(actor, taxEnabled: true);

    // Se apaga después de haber cobrado con IVA.
    final tax = TaxSettings(db);
    await tax.setEnabled(false);

    final sale = await (db.select(db.sales)
          ..where((t) => t.id.equals(conIva.saleId)))
        .getSingle();
    expect(sale.taxCents, 8000,
        reason: 'la venta vieja conserva el desglose con el que se cobró');
  });

  test('un producto puede seguir teniendo su tasa aunque el IVA esté apagado',
      () async {
    final actor = await admin();
    final cat = await catalog.createCategory(actor, 'Gorras');
    final id = await catalog.createSimpleProduct(actor,
        name: 'Gorra', categoryId: cat, basePriceCents: 1000);
    await (db.update(db.products)..where((t) => t.id.equals(id)))
        .write(const ProductsCompanion(taxRateBps: Value(1600)));

    // La tasa vive en el producto; el interruptor decide si se usa.
    expect((await catalog.productById(id))!.taxRateBps, 1600);
  });
}
