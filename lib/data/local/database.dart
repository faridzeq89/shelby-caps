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
    PriceTiers,
    Variants,
    Barcodes,
    InventoryMovements,
    Sales,
    SaleLines,
    Payments,
    Quotes,
    QuoteLines,
    LayawayTerms,
    CreditNotes,
    Customers,
    CashSessions,
    AuditLog,
    StockCounts,
    StockCountLines,
    CashMovements,
    LoyaltyTransactions,
    GiftCards,
    GiftCardTransactions,
    Expenses,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Sin argumentos abre la base local en el dispositivo. Los tests pueden
  /// inyectar un ejecutor en memoria: `AppDatabase(NativeDatabase.memory())`.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createExtras();
        },
        // Pasos aditivos e idempotentes: una base en cualquier versión previa
        // aplica en orden todos los pasos que le faltan.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // La v1 solo tenía `profiles` (con el PIN del admin ya cambiado);
            // se conserva y se crea TODO lo demás con el esquema actual (ya
            // incluye min_stock e image_path), así que aquí termina.
            for (final entity in allSchemaEntities) {
              if (entity is TableInfo && entity.actualTableName == 'profiles') {
                continue;
              }
              await m.create(entity);
            }
            await _createExtras();
            return;
          }
          if (from < 3) {
            // v2 → v3: tabla de movimientos de efectivo.
            await m.createTable(cashMovements);
          }
          if (from < 4) {
            // v3 → v4: punto de reorden por variante (alertas de stock bajo).
            await _addMinStockIfMissing(m);
          }
          if (from < 5) {
            // v4 → v5: imagen del producto (rediseño visual).
            await _addImagePathIfMissing(m);
          }
          if (from < 6) {
            // v5 → v6: ledger de puntos de lealtad.
            await m.createTable(loyaltyTransactions);
          }
          if (from < 7) {
            // v6 → v7: tarjetas de regalo (saldo prepagado) + su ledger.
            await m.createTable(giftCards);
            await m.createTable(giftCardTransactions);
          }
          if (from < 9) {
            // v8 → v9: precios por cantidad (mayoreo). Idempotente: crea la tabla
            // solo si no existe (una base fabricada en pruebas puede ya traerla).
            await _createTableIfMissing('price_tiers', priceTiers);
          }
          if (from < 10) {
            // v9 → v10: gastos del negocio.
            await _createTableIfMissing('expenses', expenses);
          }
          if (from < 11) {
            // v10 → v11: cotizaciones (carrito guardado, no cobrado).
            await _createTableIfMissing('quotes', quotes);
            await _createTableIfMissing('quote_lines', quoteLines);
          }
          await _createExtras();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Espera en vez de fallar si el respaldo (VACUUM) toma el lock un
          // instante: evita "database is locked" al guardar.
          await customStatement('PRAGMA busy_timeout = 5000');
        },
      );

  /// Agrega `variants.min_stock` solo si aún no existe. Idempotente: una base
  /// v2 fabricada en pruebas puede ya traer la columna, y ALTER TABLE no
  /// soporta IF NOT EXISTS.
  Future<void> _addMinStockIfMissing(Migrator m) async {
    final info = await customSelect("PRAGMA table_info('variants')").get();
    final hasColumn =
        info.any((r) => r.read<String>('name') == 'min_stock');
    if (!hasColumn) {
      await m.addColumn(variants, variants.minStock);
    }
  }

  /// Agrega `products.image_path` solo si aún no existe. Idempotente por el
  /// mismo motivo que [_addMinStockIfMissing].
  Future<void> _addImagePathIfMissing(Migrator m) async {
    final info = await customSelect("PRAGMA table_info('products')").get();
    final hasColumn =
        info.any((r) => r.read<String>('name') == 'image_path');
    if (!hasColumn) {
      await m.addColumn(products, products.imagePath);
    }
  }

  /// Crea [table] solo si aún no existe en la base (por nombre). Idempotente:
  /// `m.createTable` no soporta IF NOT EXISTS y una base fabricada en pruebas
  /// puede ya traer la tabla.
  Future<void> _createTableIfMissing(String name, TableInfo table) async {
    final row = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable.withString(name)],
    ).getSingleOrNull();
    if (row == null) await createMigrator().createTable(table);
  }

  /// Índices, la vista `variant_stock` y los triggers de inmutabilidad del
  /// ledger. Idempotente (IF NOT EXISTS) para servir en creación y upgrade.
  Future<void> _createExtras() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_price_tiers_product '
        'ON price_tiers (product_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_expenses_created '
        'ON expenses (created_at)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_quote_lines_quote '
        'ON quote_lines (quote_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_movements_variant_loc '
        'ON inventory_movements (variant_id, location_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_lines_sale ON sale_lines (sale_id)');
    // Reportes (recomendaciones, inventario muerto, ventas por variante) filtran
    // sale_lines por variant_id: sin este índice hacen escaneo completo y se traban.
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_sale_lines_variant ON sale_lines (variant_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_payments_sale ON payments (sale_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_variants_product ON variants (product_id)');
    // Vitrina/búsqueda con catálogo grande: filtrar por categoría y ordenar por
    // nombre sin escanear toda la tabla.
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_category ON products (category_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products (name)');

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
