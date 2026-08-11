import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Gastos del negocio: alta, borrado, listado y totales por periodo. Registro
/// simple e independiente del corte de caja. Las acciones sensibles exigen rol
/// ([Permissions.canManageExpenses]) y quedan en `audit_log`.
class ExpenseRepository {
  ExpenseRepository(this._db);
  final AppDatabase _db;

  /// Categorías sugeridas en la UI (el usuario puede escribir otra).
  static const suggestedCategories = <String>[
    'Renta',
    'Servicios',
    'Proveedor',
    'Sueldos',
    'Publicidad',
    'Mantenimiento',
    'Transporte',
    'Otros',
  ];

  void _require(Profile actor) {
    if (!Permissions.canManageExpenses(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede administrar gastos');
    }
  }

  Future<int> addExpense({
    required Profile actor,
    required String category,
    required int amountCents,
    String? note,
  }) async {
    _require(actor);
    final cat = category.trim();
    if (cat.isEmpty) throw ArgumentError('La categoría es obligatoria');
    if (amountCents <= 0) throw ArgumentError('El monto debe ser mayor a cero');
    return _db.transaction(() async {
      final id = await _db.into(_db.expenses).insert(
            ExpensesCompanion.insert(
              category: cat,
              amountCents: amountCents,
              note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
              userId: Value(actor.id),
            ),
          );
      await _audit(actor, 'add_expense', id.toString(),
          '$cat \$${(amountCents / 100).toStringAsFixed(2)}');
      return id;
    });
  }

  Future<void> deleteExpense(Profile actor, int id) async {
    _require(actor);
    await _db.transaction(() async {
      await (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();
      await _audit(actor, 'delete_expense', id.toString(), 'borrado');
    });
  }

  /// Gastos más recientes primero.
  Future<List<Expense>> recent({int limit = 200}) =>
      (_db.select(_db.expenses)
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .get();

  /// Gastos del rango [from, to) (to exclusivo), recientes primero.
  Future<List<Expense>> between(DateTime from, DateTime to) =>
      (_db.select(_db.expenses)
            ..where((t) =>
                t.createdAt.isBiggerOrEqualValue(from) &
                t.createdAt.isSmallerThanValue(to))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
            ]))
          .get();

  /// Total de gastos (centavos) en el rango [from, to).
  Future<int> totalBetween(DateTime from, DateTime to) async {
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(amount_cents), 0) AS total FROM expenses '
      'WHERE created_at >= ? AND created_at < ?',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
      readsFrom: {_db.expenses},
    ).getSingle();
    return row.read<int>('total');
  }

  Future<void> _audit(
      Profile actor, String action, String entityId, String detail) {
    return _db.into(_db.auditLog).insert(
          AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: 'expense',
            entityId: Value(entityId),
            detail: Value(detail),
          ),
        );
  }
}
