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
