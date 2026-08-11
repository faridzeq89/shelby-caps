import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/permissions.dart';
import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/expense_repository.dart';

void main() {
  late AppDatabase db;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExpenseRepository(db);
  });
  tearDown(() => db.close());

  Future<Profile> profile(UserRole role) async {
    final id = await db.insertProfile(ProfilesCompanion.insert(
        name: role.name, role: role, pinSalt: 's', pinHash: 'h'));
    return (db.select(db.profiles)..where((t) => t.id.equals(id))).getSingle();
  }

  test('admin registra gasto, aparece en el listado y suma en el total', () async {
    final actor = await profile(UserRole.admin);
    await repo.addExpense(
        actor: actor, category: 'Renta', amountCents: 500000, note: 'Local');
    await repo.addExpense(
        actor: actor, category: 'Servicios', amountCents: 120000);

    final list = await repo.recent();
    expect(list, hasLength(2));

    final now = DateTime.now();
    final total = await repo.totalBetween(
        DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
    expect(total, 620000);
  });

  test('borrar gasto lo quita del total', () async {
    final actor = await profile(UserRole.admin);
    final id = await repo.addExpense(
        actor: actor, category: 'Otros', amountCents: 10000);
    await repo.deleteExpense(actor, id);
    expect(await repo.recent(), isEmpty);
  });

  test('el cajero no puede registrar gastos', () async {
    final caja = await profile(UserRole.cashier);
    expect(
      () => repo.addExpense(actor: caja, category: 'Renta', amountCents: 100),
      throwsA(isA<PermissionException>()),
    );
  });

  test('rechaza monto <= 0 y categoría vacía', () async {
    final actor = await profile(UserRole.admin);
    expect(
      () => repo.addExpense(actor: actor, category: 'Renta', amountCents: 0),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.addExpense(actor: actor, category: '  ', amountCents: 100),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('totalBetween respeta el rango (to exclusivo)', () async {
    final actor = await profile(UserRole.admin);
    await repo.addExpense(actor: actor, category: 'Renta', amountCents: 1000);
    final now = DateTime.now();
    // Rango que NO incluye hoy → 0.
    final past = await repo.totalBetween(
        now.subtract(const Duration(days: 10)),
        now.subtract(const Duration(days: 5)));
    expect(past, 0);
  });
}
