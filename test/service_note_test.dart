import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/sales_repository.dart';
import 'package:pos_boutique/data/repositories/service_note_repository.dart';

void main() {
  late AppDatabase db;
  late ServiceNoteRepository notes;
  late SalesRepository sales;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notes = ServiceNoteRepository(db);
    sales = SalesRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> cashier() async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: 'Caja', role: UserRole.cashier, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

  test('crea la nota con folio propio y sin venta ligada', () async {
    final n = await notes.create(
      customerName: 'Juan Pérez',
      items: const [
        ServiceItem(
            itemType: ServiceItemType.tenis, brand: 'Nike', color: 'Blanco'),
      ],
    );
    expect(n.folio.startsWith('SV-'), isTrue);
    expect(n.customerName, 'Juan Pérez');
    expect(n.itemType, ServiceItemType.tenis);
    expect(n.saleId, isNull);

    final second = await notes.create(
      customerName: 'Ana',
      items: const [ServiceItem(itemType: ServiceItemType.gorra)],
    );
    expect(second.folio, isNot(n.folio));
    expect(second.brand, isNull);
  });

  test('una nota guarda varias piezas y las devuelve', () async {
    final n = await notes.create(
      customerName: 'Marta',
      items: const [
        ServiceItem(itemType: ServiceItemType.tenis, brand: 'Nike', qty: 4),
        ServiceItem(itemType: ServiceItemType.gorra, color: 'Rojo'),
      ],
    );
    // El encabezado denormaliza la 1ª pieza y suma las cantidades para el
    // resumen de la lista.
    expect(n.itemType, ServiceItemType.tenis);
    expect(n.brand, 'Nike');
    expect(n.qty, 5);

    final items = serviceNoteItems(n);
    expect(items.length, 2);
    expect(items[0].itemType, ServiceItemType.tenis);
    expect(items[0].qty, 4);
    expect(items[1].itemType, ServiceItemType.gorra);
    expect(items[1].color, 'Rojo');
  });

  test('nota vieja sin items_json cae a la pieza del encabezado', () async {
    final n = await notes.create(
      customerName: 'Pedro',
      items: const [ServiceItem(itemType: ServiceItemType.bolsa, brand: 'Gucci')],
    );
    // Simula una nota anterior a la columna items_json.
    await (db.update(db.serviceNotes)..where((t) => t.id.equals(n.id)))
        .write(const ServiceNotesCompanion(itemsJson: Value(null)));
    final vieja = (await notes.byId(n.id))!;
    expect(vieja.itemsJson, isNull);
    final items = serviceNoteItems(vieja);
    expect(items.length, 1);
    expect(items.single.itemType, ServiceItemType.bolsa);
    expect(items.single.brand, 'Gucci');
  });

  test('updateDetails reemplaza las piezas', () async {
    final n = await notes.create(
      customerName: 'Sofía',
      items: const [ServiceItem(itemType: ServiceItemType.tenis, qty: 1)],
    );
    await notes.updateDetails(
      n.id,
      customerName: 'Sofía',
      items: const [
        ServiceItem(itemType: ServiceItemType.gorra, qty: 2),
        ServiceItem(itemType: ServiceItemType.bolsa, qty: 1),
      ],
    );
    final v = (await notes.byId(n.id))!;
    expect(v.itemType, ServiceItemType.gorra);
    expect(v.qty, 3);
    expect(serviceNoteItems(v).length, 2);
  });

  test('venta directa cobra sin productos y sin mover inventario', () async {
    final caja = await cashier();
    final loc = await location();

    final r = await sales.sellDirect(
      cashier: caja,
      locationId: loc,
      amountCents: 15000,
      payments: const [PaymentInput(PaymentMethod.cash, 15000)],
      description: 'Servicio SV-000001: Tenis — Juan Pérez',
    );

    final sale = await (db.select(db.sales)
          ..where((t) => t.id.equals(r.saleId)))
        .getSingle();
    expect(sale.totalCents, 15000);
    expect(sale.notes, 'Servicio SV-000001: Tenis — Juan Pérez');

    expect(await (db.select(db.saleLines)..where((t) => t.saleId.equals(r.saleId))).get(),
        isEmpty);
    expect(await db.select(db.inventoryMovements).get(), isEmpty);

    final pays = await (db.select(db.payments)
          ..where((t) => t.saleId.equals(r.saleId)))
        .get();
    expect(pays.single.method, PaymentMethod.cash);
    expect(pays.single.amountCents, 15000);
  });

  test('cobrar liga la nota a la venta (pendiente → cobrada)', () async {
    final caja = await cashier();
    final loc = await location();
    final n = await notes.create(
        customerName: 'Luis',
        items: const [ServiceItem(itemType: ServiceItemType.bolsa)]);

    final r = await sales.sellDirect(
      cashier: caja,
      locationId: loc,
      amountCents: 20000,
      payments: const [PaymentInput(PaymentMethod.cash, 20000)],
      description: 'Servicio ${n.folio}',
    );
    await notes.markPaid(n.id, r.saleId);

    final updated = await notes.byId(n.id);
    expect(updated!.saleId, r.saleId);
  });
}
