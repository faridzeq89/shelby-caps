import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/import_repository.dart';

void main() {
  late AppDatabase db;
  late ImportRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ImportRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> user(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> location() =>
      db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));

  const csv =
      'producto,categoria,talla,color,precio,costo,stock,codigo\n'
      'Blusa Flor,Blusas,M,Rojo,299,120,5,\n'
      'Blusa Flor,Blusas,G,Rojo,299,120,3,7501234567890\n'
      'Pantalón Lino,Pantalones,28,Beige,499,210,2,';

  test('parsea CSV con comas y detecta columnas', () {
    final p = repo.parse(csv);
    expect(p.ok, isTrue);
    expect(p.rows.length, 3);
    expect(p.rows.first.product, 'Blusa Flor');
    expect(p.rows.first.priceCents, 29900);
    expect(p.rows.first.costCents, 12000);
    expect(p.rows.first.stock, 5);
    expect(p.rows[1].code, '7501234567890');
  });

  test('parsea TSV (copiado de Excel con tabuladores)', () {
    final tsv = csv.replaceAll(',', '\t');
    final p = repo.parse(tsv);
    expect(p.ok, isTrue);
    expect(p.rows.length, 3);
  });

  test('reporta líneas con precio inválido o faltantes', () {
    final p = repo.parse(
        'producto,categoria,precio\nSoloNombre,,abc\n,Cat,100');
    expect(p.rows, isEmpty);
    expect(p.errors.length, 2);
  });

  test('importa: crea categorías, productos, variantes, códigos y stock', () async {
    final admin = await user(UserRole.admin);
    final locId = await location();
    final p = repo.parse(csv);
    final sum = await repo.import(admin, p.rows, locationId: locId);

    expect(sum.productsCreated, 2); // Blusa Flor, Pantalón Lino
    expect(sum.variantsCreated, 3);
    expect(sum.unitsReceived, 10); // 5 + 3 + 2

    // Stock del ledger para una variante.
    final variants = await db.select(db.variants).get();
    expect(variants.length, 3);
    final rojoM = variants.firstWhere((v) => v.size == 'M' && v.color == 'Rojo');
    expect((await db.stockFor(rojoM.id)).onHand, 5);

    // Código de proveedor respetado; internos generados para el resto.
    final codes = await db.select(db.barcodes).get();
    expect(codes.any((c) => c.code == '7501234567890'), isTrue);
    expect(codes.where((c) => c.code.startsWith('MB')).length, 2);
  });

  test('reimportar omite variantes ya existentes (idempotente por SKU)', () async {
    final admin = await user(UserRole.admin);
    final locId = await location();
    final p = repo.parse(csv);
    await repo.import(admin, p.rows, locationId: locId);
    final again = await repo.import(admin, repo.parse(csv).rows, locationId: locId);
    expect(again.variantsCreated, 0);
    expect(again.variantsSkipped, 3);
  });

  test('un cajero no puede importar', () async {
    final cashier = await user(UserRole.cashier);
    final locId = await location();
    final p = repo.parse(csv);
    expect(() => repo.import(cashier, p.rows, locationId: locId),
        throwsA(isA<PermissionException>()));
  });
}
