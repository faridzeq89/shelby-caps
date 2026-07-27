import 'package:drift/drift.dart';

import '../local/database.dart';

/// Totales de un cliente para su ficha (CRM ligero).
class CustomerStats {
  const CustomerStats({
    required this.visits,
    required this.spentCents,
    this.lastVisit,
  });

  final int visits; // compras que cuentan (completadas/devueltas)
  final int spentCents; // gasto de por vida
  final DateTime? lastVisit;
}

/// Clientes y su historial de compras. No cambia el esquema: usa `customers` y
/// `sales.customerId`, que existen desde la Fase 2.
class CustomerRepository {
  CustomerRepository(this._db);
  final AppDatabase _db;

  // Estados de venta que cuentan como compra real del cliente.
  static const _countedStatuses = "('completed','returned','partialReturn')";

  Future<int> create({
    required String name,
    String? phone,
    String? email,
    String? notes,
  }) {
    return _db.into(_db.customers).insert(CustomersCompanion.insert(
          name: name,
          phone: Value(phone),
          email: Value(email),
          notes: Value(notes),
        ));
  }

  Future<void> update({
    required int id,
    required String name,
    String? phone,
    String? email,
    String? notes,
  }) async {
    await (_db.update(_db.customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        name: Value(name),
        phone: Value(phone),
        email: Value(email),
        notes: Value(notes),
      ),
    );
  }

  Future<Customer?> byId(int id) =>
      (_db.select(_db.customers)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<Customer>> all({int limit = 300}) =>
      (_db.select(_db.customers)
            ..orderBy([(t) => OrderingTerm(expression: t.name)])
            ..limit(limit))
          .get();

  /// Búsqueda por nombre o teléfono (para asignar en la venta o en Admin).
  Future<List<Customer>> search(String query, {int limit = 50}) {
    final like = '%${query.trim()}%';
    return (_db.select(_db.customers)
          ..where((t) => t.name.like(like) | t.phone.like(like))
          ..orderBy([(t) => OrderingTerm(expression: t.name)])
          ..limit(limit))
        .get();
  }

  /// Historial de compras (ventas del cliente, más recientes primero).
  Future<List<Sale>> history(int customerId, {int limit = 100}) =>
      (_db.select(_db.sales)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.createdAt, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .get();

  /// Totales: número de compras, gasto de por vida y última visita.
  Future<CustomerStats> stats(int customerId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS visits, COALESCE(SUM(total_cents), 0) AS spent, '
      'MAX(created_at) AS last FROM sales '
      'WHERE customer_id = ? AND status IN $_countedStatuses',
      variables: [Variable.withInt(customerId)],
      readsFrom: {_db.sales},
    ).getSingle();
    final lastSec = row.readNullable<int>('last');
    return CustomerStats(
      visits: row.read<int>('visits'),
      spentCents: row.read<int>('spent'),
      lastVisit: lastSec == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastSec * 1000),
    );
  }
}
