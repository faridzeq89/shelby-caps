import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../local/database.dart';

/// Una fila de importación ya validada (nivel variante/SKU).
class ImportRow {
  ImportRow({
    required this.lineNo,
    required this.product,
    required this.category,
    required this.size,
    required this.color,
    required this.priceCents,
    required this.costCents,
    required this.stock,
    required this.code,
  });
  final int lineNo;
  final String product;
  final String category;
  final String? size;
  final String? color;
  final int priceCents;
  final int costCents;
  final int stock;
  final String? code; // código de proveedor; si es null se genera interno MB
}

class ParseResult {
  ParseResult(this.rows, this.errors);
  final List<ImportRow> rows;
  final List<String> errors; // mensajes por línea con problema
  bool get ok => errors.isEmpty && rows.isNotEmpty;
}

class ImportSummary {
  ImportSummary(
      {required this.productsCreated,
      required this.variantsCreated,
      required this.variantsSkipped,
      required this.unitsReceived});
  final int productsCreated;
  final int variantsCreated;
  final int variantsSkipped;
  final int unitsReceived;
}

/// Importación masiva del catálogo desde texto pegado (CSV con comas o TSV
/// copiado de Excel con tabuladores). Respeta el ledger: el stock inicial entra
/// como movimiento `receipt`.
class ImportRepository {
  ImportRepository(this._db);
  final AppDatabase _db;

  static const columns = 'producto, categoria, talla, color, precio, costo, stock, codigo';

  // ---------------------------------------------------------------------------
  // Parseo / validación
  // ---------------------------------------------------------------------------
  ParseResult parse(String content) {
    final rows = <ImportRow>[];
    final errors = <String>[];
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return ParseResult(rows, ['El texto está vacío']);

    final delimiter = lines.first.contains('\t') ? '\t' : ',';
    final header = _split(lines.first, delimiter).map(_norm).toList();
    int col(String name) => header.indexOf(name);
    final iProd = col('producto'), iCat = col('categoria'), iPrecio = col('precio');
    if (iProd < 0 || iCat < 0 || iPrecio < 0) {
      return ParseResult(rows,
          ['El encabezado debe incluir al menos: producto, categoria, precio.\nColumnas: $columns']);
    }
    final iTalla = col('talla'), iColor = col('color'),
        iCosto = col('costo'), iStock = col('stock'), iCodigo = col('codigo');

    for (var i = 1; i < lines.length; i++) {
      final f = _split(lines[i], delimiter);
      String? at(int idx) =>
          (idx >= 0 && idx < f.length && f[idx].trim().isNotEmpty)
              ? f[idx].trim()
              : null;
      final prod = at(iProd), cat = at(iCat);
      final priceStr = at(iPrecio);
      final lineNo = i + 1;
      if (prod == null || cat == null) {
        errors.add('Línea $lineNo: falta producto o categoría');
        continue;
      }
      final price = _cents(priceStr);
      if (price == null) {
        errors.add('Línea $lineNo: precio inválido ("$priceStr")');
        continue;
      }
      final cost = _cents(at(iCosto)) ?? 0;
      final stock = int.tryParse(at(iStock) ?? '0') ?? 0;
      rows.add(ImportRow(
        lineNo: lineNo,
        product: prod,
        category: cat,
        size: at(iTalla),
        color: at(iColor),
        priceCents: price,
        costCents: cost,
        stock: stock < 0 ? 0 : stock,
        code: at(iCodigo),
      ));
    }
    if (rows.isEmpty && errors.isEmpty) errors.add('No hay filas de datos');
    return ParseResult(rows, errors);
  }

  // ---------------------------------------------------------------------------
  // Importación
  // ---------------------------------------------------------------------------
  Future<ImportSummary> import(Profile actor, List<ImportRow> rows,
      {required int locationId}) async {
    if (!Permissions.canManageCatalog(actor.role)) {
      throw PermissionException(
          'El rol ${actor.role.name} no puede importar catálogo');
    }
    var productsCreated = 0, variantsCreated = 0, variantsSkipped = 0, units = 0;

    await _db.transaction(() async {
      final catByName = <String, int>{};
      final prodByKey = <String, int>{};
      var seq = await _maxInternalBarcodeNumber();

      for (final c in await _db.select(_db.categories).get()) {
        catByName[_norm(c.name)] = c.id;
      }

      for (final r in rows) {
        // Categoría.
        final catKey = _norm(r.category);
        var catId = catByName[catKey];
        catId ??= await () async {
          final id = await _db.into(_db.categories).insert(
              CategoriesCompanion.insert(name: r.category));
          catByName[catKey] = id;
          return id;
        }();

        // Producto (por categoría + nombre).
        final prodKey = '$catId|${_norm(r.product)}';
        var prodId = prodByKey[prodKey];
        if (prodId == null) {
          final existing = await (_db.select(_db.products)
                ..where((t) => t.categoryId.equals(catId!) & t.name.equals(r.product)))
              .getSingleOrNull();
          if (existing != null) {
            prodId = existing.id;
          } else {
            prodId = await _db.into(_db.products).insert(ProductsCompanion.insert(
                name: r.product, categoryId: catId, basePriceCents: r.priceCents));
            productsCreated++;
          }
          prodByKey[prodKey] = prodId;
        }

        // Variante (por producto + talla + color).
        final sku = _sku(prodId, r.size ?? '', r.color ?? '');
        final existingVar = await (_db.select(_db.variants)
              ..where((t) => t.sku.equals(sku)))
            .getSingleOrNull();
        if (existingVar != null) {
          variantsSkipped++;
          continue;
        }
        final varId = await _db.into(_db.variants).insert(VariantsCompanion.insert(
          productId: prodId,
          sku: sku,
          size: Value(r.size),
          color: Value(r.color),
          costCents: Value(r.costCents),
          priceCentsOverride:
              Value(r.priceCents != 0 ? r.priceCents : null),
        ));
        variantsCreated++;

        // Código: proveedor si viene, si no interno MB.
        if (r.code != null) {
          await _db.into(_db.barcodes).insert(BarcodesCompanion.insert(
              variantId: varId, code: r.code!, source: BarcodeSource.supplier));
        } else {
          seq++;
          await _db.into(_db.barcodes).insert(BarcodesCompanion.insert(
              variantId: varId,
              code: 'MB${seq.toString().padLeft(10, '0')}',
              source: BarcodeSource.internal));
        }

        // Stock inicial como receipt.
        if (r.stock > 0) {
          await _db.into(_db.inventoryMovements).insert(
              InventoryMovementsCompanion.insert(
                  variantId: varId,
                  locationId: locationId,
                  qty: r.stock,
                  type: MovementType.receipt,
                  userId: Value(actor.id),
                  reason: const Value('Importación de catálogo')));
          units += r.stock;
        }
      }

      await _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: 'import_catalog',
            entityType: 'catalog',
            detail: Value(
                'productos=$productsCreated; variantes=$variantsCreated; omitidas=$variantsSkipped'),
          ));
    });

    return ImportSummary(
        productsCreated: productsCreated,
        variantsCreated: variantsCreated,
        variantsSkipped: variantsSkipped,
        unitsReceived: units);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  List<String> _split(String line, String delimiter) {
    if (delimiter == '\t') return line.split('\t');
    // CSV con comillas.
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    return out;
  }

  String _norm(String v) => v.trim().toLowerCase();

  /// Convierte "$1,234.50" o "1234.5" a centavos. Null si no es número.
  int? _cents(String? v) {
    if (v == null) return null;
    final clean = v.replaceAll(RegExp(r'[^\d.\-]'), '');
    final d = double.tryParse(clean);
    if (d == null) return null;
    return (d * 100).round();
  }

  String _san(String v) => v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  String _sku(int productId, String size, String color) =>
      'P$productId-${_san(size)}-${_san(color)}';

  Future<int> _maxInternalBarcodeNumber() async {
    final row = await _db
        .customSelect(
          "SELECT COALESCE(MAX(CAST(SUBSTR(code, 3) AS INTEGER)), 0) AS n "
          "FROM barcodes WHERE source = 'internal'",
          readsFrom: {_db.barcodes},
        )
        .getSingle();
    return row.read<int>('n');
  }
}
