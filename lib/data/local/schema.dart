import 'package:drift/drift.dart';

// ===========================================================================
// Enums. `textEnum` guarda el NOMBRE del valor (no el índice): no reordenar ni
// renombrar sin migración.
// ===========================================================================

enum UserRole { admin, manager, cashier }

enum BarcodeSource { supplier, internal }

/// Tipos de movimiento del ledger de inventario.
/// `receipt/sale/returned/adjustment/count` afectan `on_hand`.
/// `reserve/release` afectan `reserved` (apartados), no `on_hand`.
enum MovementType { receipt, sale, returned, adjustment, reserve, release, count }

enum SaleStatus { completed, layaway, cancelled, returned, partialReturn }

enum PaymentMethod { cash, card, transfer, creditNote, giftCard }

enum LayawayStatus { active, completed, expired, cancelled }

/// Estado de una cotización. `open` = vigente; `converted` = ya se pasó a venta;
/// `cancelled` = descartada.
enum QuoteStatus { open, converted, cancelled }

enum CreditNoteStatus { active, redeemed, expired, cancelled }

enum CashSessionStatus { open, closed }

enum StockCountStatus { open, applied, cancelled }

enum CashMovementKind { deposit, withdrawal }

/// Movimiento del ledger de puntos de lealtad. `earn` gana (+), `redeem` canjea
/// (−), `adjust` corrección manual (con signo).
enum LoyaltyType { earn, redeem, adjust }

/// Movimientos de una tarjeta de regalo. `issue` = emisión/recarga (+),
/// `redeem` = canje en una venta (−), `adjust` = corrección manual.
enum GiftCardTxType { issue, redeem, adjust }

// ===========================================================================
// Operación / seguridad
// ===========================================================================

/// Usuarios del punto de venta. Login por PIN (ver [pinHash]/[pinSalt]).
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get role => textEnum<UserRole>()();
  TextColumn get pinSalt => text()();
  TextColumn get pinHash => text()();
  BoolColumn get mustChangePin =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Sucursales. Se incluye desde el día uno (una sola fila) para no migrar el
/// ledger después.
class Locations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// Contador de folios por prefijo de dispositivo (`T1-000123`).
class FolioSequences extends Table {
  TextColumn get prefix => text()();
  IntColumn get lastValue => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {prefix};
}

/// Configuración simple clave/valor (p. ej. prefijo del dispositivo).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ===========================================================================
// Catálogo
// ===========================================================================

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  // Auto-referencia (jerarquía). Sin FK dura para evitar líos de orden.
  IntColumn get parentId => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Proveedor: quién surte la mercancía. Registro tipo directorio (nombre,
/// teléfono, contacto). Se puede ligar a productos para saber a quién recomprar.
class Suppliers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get phone => text().nullable()();
  TextColumn get contact => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Estilo/modelo padre. El precio y el impuesto viven aquí; la variante puede
/// sobrescribir el precio.
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  IntColumn get categoryId => integer().references(Categories, #id)();
  // Proveedor que surte el producto (opcional). Sin FK dura para no complicar
  // el orden de creación/restauración.
  IntColumn get supplierId => integer().nullable()();
  TextColumn get brand => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get basePriceCents => integer()();
  // IVA por producto en puntos base: 1600 = 16.00%.
  IntColumn get taxRateBps => integer().withDefault(const Constant(1600))();
  // Imagen del producto: ruta de archivo local (foto capturada/optimizada) o
  // clave de asset ('assets/...') para el catálogo de demo. Nulo => sin foto.
  TextColumn get imagePath => text().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Precios por cantidad (**mayoreo**). Un producto puede tener 0..n escalones:
/// cuando la cantidad del producto en el carrito alcanza `minQty`, el precio
/// unitario baja a `priceCents`. Con un solo escalón (p. ej. `minQty=10`) se
/// cubre el mayoreo típico; con varios se logra precio escalonado (≥10, ≥50…).
/// Aplica a TODAS las variantes del producto y la cantidad se cuenta **surtida**
/// entre variantes (10 gorras aunque sean tallas/colores distintos).
class PriceTiers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get minQty => integer()();
  IntColumn get priceCents => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// El SKU real: lo que se vende y se cuenta.
class Variants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get sku => text().unique()();
  TextColumn get size => text().nullable()();
  TextColumn get color => text().nullable()();
  // Atributos raros (material/temporada) como JSON.
  TextColumn get attributes => text().nullable()();
  // Nulo => hereda el precio del producto.
  IntColumn get priceCentsOverride => integer().nullable()();
  IntColumn get costCents => integer().withDefault(const Constant(0))();
  // Punto de reorden por variante. Nulo => usa el default global
  // (AppSettings `low_stock_default`). Alimenta las alertas de stock bajo.
  IntColumn get minStock => integer().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Un SKU puede tener varios códigos (UPC de proveedor + interno propio).
class Barcodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get variantId => integer().references(Variants, #id)();
  TextColumn get code => text().unique()();
  TextColumn get source => textEnum<BarcodeSource>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ===========================================================================
// Inventario — ledger append-only (la verdad del stock)
// ===========================================================================

class InventoryMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get variantId => integer().references(Variants, #id)();
  IntColumn get locationId => integer().references(Locations, #id)();
  IntColumn get qty => integer()(); // con signo
  TextColumn get type => textEnum<MovementType>()();
  TextColumn get referenceType => text().nullable()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get reason => text().nullable()();
  IntColumn get userId => integer().nullable().references(Profiles, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ===========================================================================
// Venta
// ===========================================================================

class Sales extends Table {
  // UUID generado en el cliente (idempotencia).
  TextColumn get id => text()();
  TextColumn get folio => text().unique()();
  IntColumn get locationId => integer().references(Locations, #id)();
  IntColumn get cashierId => integer().references(Profiles, #id)();
  IntColumn get salespersonId =>
      integer().nullable().references(Profiles, #id)();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  TextColumn get status => textEnum<SaleStatus>()();
  IntColumn get subtotalCents => integer()();
  IntColumn get discountCents => integer().withDefault(const Constant(0))();
  IntColumn get taxCents => integer()();
  IntColumn get totalCents => integer()();
  TextColumn get rfc => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get saleId => text().references(Sales, #id)();
  IntColumn get variantId => integer().references(Variants, #id)();
  IntColumn get qty => integer()(); // negativo en devolución
  IntColumn get unitPriceCents => integer()();
  IntColumn get discountCents => integer().withDefault(const Constant(0))();
  IntColumn get taxCents => integer()();
  IntColumn get lineTotalCents => integer()();
  // Para devoluciones: apunta a la línea original.
  IntColumn get originalSaleLineId => integer().nullable()();
}

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get method => textEnum<PaymentMethod>()();
  IntColumn get amountCents => integer()();
  TextColumn get reference => text().nullable()();
  IntColumn get cashierId => integer().references(Profiles, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Cotización: un carrito guardado que todavía no se cobra. Se comparte en PDF
/// y luego se "pasa a venta". NO afecta inventario ni caja hasta convertirse.
class Quotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get folio => text().unique()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  TextColumn get status => textEnum<QuoteStatus>()();
  IntColumn get subtotalCents => integer()();
  IntColumn get totalCents => integer()();
  TextColumn get notes => text().nullable()();
  // La venta generada al convertir (Sales.id es UUID de texto). Sin FK dura:
  // es una referencia informativa, evita líos de orden al respaldar/restaurar.
  TextColumn get convertedSaleId => text().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class QuoteLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get quoteId => integer().references(Quotes, #id)();
  IntColumn get variantId => integer().references(Variants, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPriceCents => integer()();
  IntColumn get lineDiscountCents => integer().withDefault(const Constant(0))();
  IntColumn get lineTotalCents => integer()();
}

/// Un apartado es una venta con `status='layaway'` + estos términos.
class LayawayTerms extends Table {
  TextColumn get saleId => text().references(Sales, #id)();
  IntColumn get depositRequiredCents => integer()();
  DateTimeColumn get dueDate => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();
  TextColumn get status => textEnum<LayawayStatus>()();

  @override
  Set<Column> get primaryKey => {saleId};
}

/// Notas de crédito / saldo a favor (devoluciones, apartados vencidos).
class CreditNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  TextColumn get originSaleId => text().nullable().references(Sales, #id)();
  IntColumn get amountCents => integer()();
  IntColumn get balanceCents => integer()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get status => textEnum<CreditNoteStatus>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ===========================================================================
// Gastos del negocio
// ===========================================================================

/// Gasto del negocio (renta, servicios, pago a proveedor, etc.). Es un registro
/// simple e independiente del corte de caja: sirve para el reporte de gastos y
/// la ganancia neta (ventas − gastos). La `category` es texto libre con
/// sugerencias en la UI.
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get category => text().withLength(min: 1, max: 40)();
  IntColumn get amountCents => integer()();
  TextColumn get note => text().nullable()();
  IntColumn get userId => integer().nullable().references(Profiles, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ===========================================================================
// Clientes y caja
// ===========================================================================

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class CashSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get locationId => integer().references(Locations, #id)();
  IntColumn get openingFloatCents => integer()();
  IntColumn get closingCountCents => integer().nullable()();
  IntColumn get expectedCents => integer().nullable()();
  IntColumn get varianceCents => integer().nullable()();
  IntColumn get openedBy => integer().references(Profiles, #id)();
  IntColumn get closedBy => integer().nullable().references(Profiles, #id)();
  DateTimeColumn get openedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get status => textEnum<CashSessionStatus>()();
}

/// Bitácora de acciones sensibles (cambios de precio, cancelaciones, etc.).
class AuditLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable().references(Profiles, #id)();
  TextColumn get action => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text().nullable()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ===========================================================================
// Conteo físico
// ===========================================================================

class StockCounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get locationId => integer().references(Locations, #id)();
  TextColumn get status => textEnum<StockCountStatus>()();
  IntColumn get createdBy => integer().references(Profiles, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get appliedAt => dateTime().nullable()();
}

class StockCountLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get countId => integer().references(StockCounts, #id)();
  IntColumn get variantId => integer().references(Variants, #id)();
  IntColumn get countedQty => integer()();
  IntColumn get systemQty => integer()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Entradas y salidas de efectivo del cajón durante un turno (retiros,
/// depósitos), aparte de las ventas.
class CashMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer().references(CashSessions, #id)();
  TextColumn get kind => textEnum<CashMovementKind>()();
  IntColumn get amountCents => integer()();
  TextColumn get reason => text().nullable()();
  IntColumn get userId => integer().nullable().references(Profiles, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Ledger de puntos de lealtad (append-only). El saldo de un cliente es la suma
/// de sus `points`. Ligado a la venta que los generó/canjeó cuando aplica.
class LoyaltyTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get customerId => integer().references(Customers, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  IntColumn get points => integer()(); // + gana, − canjea
  TextColumn get type => textEnum<LoyaltyType>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Tarjeta de regalo (saldo prepagado). El `code` lo genera la app y es único;
/// el saldo es la suma de sus `gift_card_transactions`.
class GiftCards extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get customerId => integer().nullable().references(Customers, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Ledger append-only de la tarjeta de regalo. + emisión/recarga, − canje.
class GiftCardTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId => integer().references(GiftCards, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  IntColumn get amountCents => integer()(); // + carga, − canje
  TextColumn get type => textEnum<GiftCardTxType>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
