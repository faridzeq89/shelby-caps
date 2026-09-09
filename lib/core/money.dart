/// Desglose de IVA de un monto con impuesto incluido.
class TaxBreakdown {
  const TaxBreakdown({required this.baseCents, required this.taxCents});
  final int baseCents;
  final int taxCents;
}

/// IVA **incluido**: desglosa un total hacia atrás. `taxRateBps` en puntos base
/// (1600 = 16%). Todo en enteros; el redondeo se hace una sola vez sobre el
/// monto dado (por eso conviene desglosar a nivel del ticket, no por línea).
TaxBreakdown taxIncludedBreakdown(int totalCents, int taxRateBps) {
  final base = ((totalCents * 10000) / (10000 + taxRateBps)).round();
  return TaxBreakdown(baseCents: base, taxCents: totalCents - base);
}

/// Aplica el descuento de OFERTA de un producto a un precio de menudeo.
/// [kind] = 'percent' ([value] 1..100) o 'fixed' ([value] centavos). Nulo o
/// value<=0 => sin descuento. Nunca baja de 0. Es la misma regla que usa la
/// tienda y el servidor, para que el precio de oferta cuadre en todos lados.
int discountedPrice(int baseCents, String? kind, int? value) {
  if (kind == null || value == null || value <= 0) return baseCents;
  final off = kind == 'percent'
      ? (baseCents * value / 100).round()
      : value;
  final result = baseCents - off;
  return result < 0 ? 0 : result;
}
