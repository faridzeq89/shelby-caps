import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v2→v3 agrega cash_movements sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v3');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Crea la base actual (v3) y guarda un perfil.
    var db = AppDatabase(NativeDatabase(file));
    await db.insertProfile(ProfilesCompanion.insert(
        name: 'Administrador', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    await db.close();

    // 2) Simula una base v2: quita cash_movements y baja el user_version.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE cash_movements');
    raw.execute('PRAGMA user_version = 2');
    raw.dispose();

    // 3) Reabre: debe correr onUpgrade v2→v3 y recrear la tabla.
    db = AppDatabase(NativeDatabase(file));
    expect(await db.allProfiles(), hasLength(1));

    // cash_movements ya funciona.
    final locId =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final profId = (await db.allProfiles()).first.id;
    final sessId = await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        locationId: locId,
        openingFloatCents: 0,
        openedBy: profId,
        status: CashSessionStatus.open));
    await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
        sessionId: sessId,
        kind: CashMovementKind.withdrawal,
        amountCents: 100));
    expect(await db.select(db.cashMovements).get(), hasLength(1));

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
