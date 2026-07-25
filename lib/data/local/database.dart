import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'schema.dart';

export 'schema.dart';

part 'database.g.dart';

/// Resultado de stock por variante, derivado del ledger (nunca un campo).
class VariantStockData {
  const VariantStockData({
    required this.variantId,
    required this.onHand,
    required this.reserved,
  });

  final int variantId;
  final int onHand;
  final int reserved;

  /// Lo que realmente se puede vender: en tienda menos lo apartado.
  int get available => onHand - reserved;
}

@DriftDatabase(
  tables: [
    Profiles,
    Locations,
    FolioSequences,
    AppSettings,
    Categories,
    Products,
    Variants,
    Barcodes,
    InventoryMovements,
    Sales,
    SaleLines,
    Payments,
    LayawayTerms,
    CreditNotes,
    Customers,
    CashSessions,
    AuditLog,
    StockCounts,
    StockCountLines,
    CashMovements,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Sin argumentos abre la base local en el dispositivo. Los tests pueden
  /// inyectar un ejecutor en memoria: `AppDatabase(NativeDatabase.memory())`.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createExtras();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // La v1 solo tenía `profiles` (con el PIN del admin ya cambiado);
            // se conserva y se crea todo lo demás (incluye cash_movements).
            for (final entity in allSchemaEntities) {
              if (entity is TableInfo && entity.actualTableName == 'profiles') {
                continue;
              }
              await m.create(entity);
            }
            await _createExtras();
          } else if (from < 3) {
            // v2 → v3: solo faltaba la tabla de movimientos de efectivo.
            await m.createTable(cashMovements);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Índices, la vista `variant_stock` y los triggers de inmutabilidad del
  /// ledger. Idempotente (IF NOT EXISTS) para servir en creación y upgrade.
  Future<void> _createExtras() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_movements_variant_loc '
        'ON inventory_movements (variant_id, location_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_lines_sale ON sale_lines (sale_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_sale ON payments (sale_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_variants_product ON variants (product_id)');

    await customStatement('''
      CREATE VIEW IF NOT EXISTS variant_stock AS
      SELECT
        v.id AS variant_id,
        COALESCE(SUM(CASE WHEN m.type IN ('receipt','sale','returned','adjustment','count')
                          THEN m.qty ELSE 0 END), 0) AS on_hand,
        COALESCE(SUM(CASE WHEN m.type IN ('reserve','release')
                          THEN m.qty ELSE 0 END), 0) AS reserved
      FROM variants v
      LEFT JOIN inventory_movements m ON m.variant_id = v.id
      GROUP BY v.id
    ''');

    // El ledger es la verdad y es append-only: nadie edita ni borra, ni admin.
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_movements_no_update
      BEFORE UPDATE ON inventory_movements
      BEGIN SELECT RAISE(ABORT, 'inventory_movements es append-only'); END
    ''');
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_movements_no_delete
      BEFORE DELETE ON inventory_movements
      BEGIN SELECT RAISE(ABORT, 'inventory_movements es append-only'); END
    ''');
  }

  // -------------------------------------------------------------------------
  // Perfiles
  // -------------------------------------------------------------------------
  Future<List<Profile>> allProfiles() => select(profiles).get();

  Future<List<Profile>> activeProfiles() =>
      (select(profiles)..where((t) => t.active.equals(true))).get();

  Future<int> insertProfile(ProfilesCompanion entry) =>
      into(profiles).insert(entry);

  Future<bool> updateProfile(Profile entry) => update(profiles).replace(entry);

  // -------------------------------------------------------------------------
  // Stock (derivado del ledger vía la vista variant_stock)
  // -------------------------------------------------------------------------
  Future<VariantStockData> stockFor(int variantId) async {
    final row = await customSelect(
      'SELECT variant_id, on_hand, reserved FROM variant_stock WHERE variant_id = ?',
      variables: [Variable.withInt(variantId)],
      readsFrom: {variants, inventoryMovements},
    ).getSingleOrNull();
    if (row == null) {
      return VariantStockData(variantId: variantId, onHand: 0, reserved: 0);
    }
    return VariantStockData(
      variantId: row.read<int>('variant_id'),
      onHand: row.read<int>('on_hand'),
      reserved: row.read<int>('reserved'),
    );
  }

  // -------------------------------------------------------------------------
  // Folios consecutivos con prefijo de dispositivo (T1-000123)
  // -------------------------------------------------------------------------
  Future<String> devicePrefix() async {
    final row = await (select(appSettings)
          ..where((t) => t.key.equals('device_prefix')))
        .getSingleOrNull();
    return row?.value ?? 'T1';
  }

  Future<String> nextFolio(String prefix) {
    return transaction(() async {
      final current = await (select(folioSequences)
            ..where((t) => t.prefix.equals(prefix)))
          .getSingleOrNull();
      final next = (current?.lastValue ?? 0) + 1;
      await into(folioSequences).insertOnConflictUpdate(
        FolioSequencesCompanion.insert(prefix: prefix, lastValue: Value(next)),
      );
      return '$prefix-${next.toString().padLeft(6, '0')}';
    });
  }

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'boutique_pos.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
