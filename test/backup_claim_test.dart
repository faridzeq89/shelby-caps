import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/cloud_backup_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('una tablet nueva (sin ventas) NO queda reclamada sola', () async {
    final svc = CloudBackupService(db, enabled: false);
    expect(await svc.isClaimed(), isFalse);
    await svc.autoClaimIfHasData();
    expect(await svc.isClaimed(), isFalse, reason: 'sin ventas no se reclama');
  });

  test('un install con ventas se reclama automáticamente', () async {
    final svc = CloudBackupService(db, enabled: false);
    // Datos mínimos para una venta (respeta FKs).
    final loc =
        await db.into(db.locations).insert(LocationsCompanion.insert(name: 'P'));
    final prof = await db.into(db.profiles).insert(ProfilesCompanion.insert(
        name: 'A', role: UserRole.admin, pinSalt: 's', pinHash: 'h'));
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: 'u1',
          folio: 'T1-000001',
          locationId: loc,
          cashierId: prof,
          status: SaleStatus.completed,
          subtotalCents: 100,
          taxCents: 14,
          totalCents: 100,
        ));

    await svc.autoClaimIfHasData();
    expect(await svc.isClaimed(), isTrue);
  });

  test('markClaimed persiste la bandera y actualiza el caché', () async {
    final svc = CloudBackupService(db, enabled: false);
    await svc.markClaimed();
    expect(svc.isClaimedCached, isTrue);
    final row = await (db.select(db.appSettings)
          ..where((t) => t.key.equals('backup_claimed')))
        .getSingleOrNull();
    expect(row?.value, 'true');
  });

  test('backupSoon en una tablet no reclamada no revienta (guardia)', () async {
    // enabled=false => backupNow retorna temprano; verificamos que la guardia y
    // el flujo no lanzan aunque no haya nube.
    final svc = CloudBackupService(db, enabled: false);
    svc.backupSoon();
    expect(await svc.isClaimed(), isFalse);
  });

  test('el valor por defecto de isClaimedCached es false antes de cargar',
      () async {
    final svc = CloudBackupService(db, enabled: false);
    expect(svc.isClaimedCached, isFalse);
  });
}
