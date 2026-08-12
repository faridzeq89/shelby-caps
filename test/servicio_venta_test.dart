import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/catalog_repository.dart';
import 'package:pos_boutique/services/sale_handoff.dart';

/// Lo que le fallo al dueño con los servicios:
///  1. Al crearlo desaparecian precio y existencias, y quedaba invendible.
///  2. En Venta no dejaba agregarlo (el selector exigia existencia > 0).
///  3. "Pasar a venta" desde cotizaciones no hacia nada.
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

  test('un servicio con tarifa fija se crea CON precio', () async {
    final actor = await admin();
    final cat = await repo.createCategory(actor, 'Servicios');

    final id = await repo.createSimpleProduct(
      actor,
      name: 'Limpieza de gorra',
      categoryId: cat,
      basePriceCents: 15000,
      esServicio: true,
    );

    final p = await repo.productById(id);
    expect(p!.esServicio, isTrue);
    expect(p.basePriceCents, 15000,
        reason: 'si tiene tarifa fija, el precio debe quedar guardado');
  });

  test('un servicio sin tarifa se crea en cero y es vendible igual', () async {
    final actor = await admin();
    final cat = await repo.createCategory(actor, 'Servicios');

    final id = await repo.createSimpleProduct(
      actor,
      name: 'Restauración',
      categoryId: cat,
      basePriceCents: 0,
      esServicio: true,
    );

    final variants = await repo.variantsOf(id);
    expect(variants.length, 1,
        reason: 'sin variante no hay nada que agregar al carrito');

    // La existencia es cero y DEBE seguir siéndolo: un servicio no es stock.
    expect((await db.stockFor(variants.single.id)).available, 0);

    final p = await repo.productById(id);
    expect(effectivePrice(p!, variants.single), 0,
        reason: 'el precio se define al agregarlo o en la cotización');
  });

  test('un producto normal NO queda marcado como servicio', () async {
    final actor = await admin();
    final cat = await repo.createCategory(actor, 'Gorras');
    final id = await repo.createSimpleProduct(actor,
        name: 'NY Yankees', categoryId: cat, basePriceCents: 60000);
    expect((await repo.productById(id))!.esServicio, isFalse);
  });

  group('handoff de cotización a venta', () {
    test('entrega la cotización y se consume una sola vez', () {
      final handoff = SaleHandoff();
      expect(handoff.hasPending, isFalse);

      final quote = Quote(
        id: 7,
        folio: 'C-0007',
        status: QuoteStatus.open,
        subtotalCents: 15000,
        totalCents: 15000,
        createdAt: DateTime(2026, 8, 12),
      );
      handoff.send(quote);

      expect(handoff.hasPending, isTrue);
      expect(handoff.take()!.folio, 'C-0007');
      expect(handoff.take(), isNull,
          reason: 'una cotización se carga al carrito una sola vez');
    });

    test('avisa a quien escuche, que es como el shell cambia de pestaña', () {
      final handoff = SaleHandoff();
      var avisos = 0;
      handoff.addListener(() => avisos++);

      handoff.send(Quote(
        id: 1,
        folio: 'C-0001',
        status: QuoteStatus.open,
        subtotalCents: 100,
        totalCents: 100,
        createdAt: DateTime(2026, 8, 12),
      ));

      expect(avisos, 1);
    });
  });
}
