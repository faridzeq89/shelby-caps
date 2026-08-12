import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/quote_repository.dart';
import '../../services/auth_controller.dart';
import '../../services/sale_handoff.dart';
import 'quote_service.dart';
import 'ticket_service.dart';

/// Lista de cotizaciones vigentes. Se abre desde la pantalla de Venta. Al elegir
/// "Pasar a venta" se cierra devolviendo la cotización para cargarla al carrito.
class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final QuoteRepository _repo = QuoteRepository(_db);
  late final CatalogRepository _catalog = CatalogRepository(_db);
  late final CustomerRepository _customers = CustomerRepository(_db);
  late Future<List<Quote>> _future = _repo.open();

  Profile get _actor => context.read<AuthController>().currentUser!;

  void _reload() => setState(() => _future = _repo.open());

  void _toast(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));


  /// Descripción legible de cada renglón (producto talla/color).
  Future<List<QuotePdfLine>> _pdfLines(List<QuoteLine> lines) async {
    final out = <QuotePdfLine>[];
    for (final l in lines) {
      final v = await _catalog.variantById(l.variantId);
      final p = v == null ? null : await _catalog.productOfVariant(v);
      final desc = p == null
          ? 'SKU ${l.variantId}'
          : '${p.name} ${v!.size ?? ''} ${v.color ?? ''}'.trim();
      out.add(QuotePdfLine(
          desc, l.qty, l.unitPriceCents, l.lineTotalCents));
    }
    return out;
  }

  Future<void> _share(Quote q) async {
    final lines = await _repo.linesOf(q.id);
    final pdfLines = await _pdfLines(lines);
    final cfg = await TicketConfig.load(_db);
    String? customerName;
    if (q.customerId != null) {
      customerName = (await _customers.byId(q.customerId!))?.name;
    }
    try {
      await Printing.layoutPdf(
        onLayout: (_) => QuoteService.build(
          folio: q.folio,
          dateTime: q.createdAt,
          lines: pdfLines,
          totalCents: q.totalCents,
          customerName: customerName,
          expiresAt: q.expiresAt,
          notes: q.notes,
          config: cfg,
        ),
        name: 'cotizacion_${q.folio}',
      );
    } catch (e) {
      _toast('No se pudo generar el PDF: $e');
    }
  }

  Future<void> _cancel(Quote q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar cotización'),
        content: Text('¿Cancelar la cotización ${q.folio}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cancelar cotización')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.cancel(_actor, q.id);
    _reload();
  }

  /// Renglones con nombre y si son servicio, para el detalle editable.
  Future<List<_LineView>> _lineViews(int quoteId) async {
    final lines = await _repo.linesOf(quoteId);
    final out = <_LineView>[];
    for (final l in lines) {
      final v = await _catalog.variantById(l.variantId);
      final p = v == null ? null : await _catalog.productOfVariant(v);
      final desc = p == null
          ? 'SKU ${l.variantId}'
          : '${p.name} ${v!.size ?? ''} ${v.color ?? ''}'.trim();
      out.add(_LineView(l, desc, p?.esServicio ?? false));
    }
    return out;
  }

  /// Pide el precio de un renglón (para servicios cuyo precio se define al ver
  /// la prenda) y lo guarda; recalcula el total de la cotización.
  Future<void> _editLinePrice(_LineView lv) async {
    final ctrl = TextEditingController(
        text: lv.line.unitPriceCents == 0
            ? ''
            : (lv.line.unitPriceCents / 100).toStringAsFixed(2));
    final pesos = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Precio — ${lv.desc}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              prefixText: '\$', labelText: 'Precio por pieza'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context)
                  .pop(double.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (pesos == null) return;
    await _repo.updateLinePrice(_actor, lv.line.id, (pesos * 100).round());
  }

  Future<void> _openDetail(Quote quote) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FutureBuilder<(Quote, List<_LineView>)>(
                future: () async {
                  final q = await (_db.select(_db.quotes)
                        ..where((t) => t.id.equals(quote.id)))
                      .getSingle();
                  return (q, await _lineViews(quote.id));
                }(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final (q, views) = snap.data!;
                  final falta = views.any((v) => v.line.unitPriceCents == 0);
                  final theme = Theme.of(context);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Cotización ${q.folio}',
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text('Toca un renglón para ponerle o cambiar el precio.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 10),
                      ...views.map((v) {
                        final sinPrecio = v.line.unitPriceCents == 0;
                        return InkWell(
                          onTap: () async {
                            await _editLinePrice(v);
                            setSheet(() {}); // refresca el detalle
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${v.line.qty} × ${v.desc}'),
                                      if (v.esServicio)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: StatusPill('Servicio',
                                              icon: Icons.design_services),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                sinPrecio
                                    ? StatusPill('Poner precio',
                                        color: theme.colorScheme.error,
                                        icon: Icons.edit)
                                    : Text(money(v.line.lineTotalCents),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                Icon(Icons.chevron_right,
                                    size: 18, color: theme.hintColor),
                              ],
                            ),
                          ),
                        );
                      }),
                      const Divider(height: 20),
                      StatBlock(
                          label: 'Total', value: money(q.totalCents), size: 26),
                      const SizedBox(height: 12),
                      if (falta)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Ponle precio a todos los renglones antes de pasar a venta.',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: falta
                            ? null
                            : () {
                                Navigator.of(sheetCtx).pop();
                                // Se entrega por el handoff en vez de por el
                                // `pop`: así funciona igual venga de Venta, del
                                // menú lateral o de Inicio.
                                context.read<SaleHandoff>().send(q);
                                Navigator.of(context).pop();
                              },
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Pasar a venta'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _share(q);
                        },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Compartir / imprimir PDF'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _cancel(q);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Cancelar cotización'),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yy');
    return Scaffold(
      appBar: AppBar(title: const Text('Por cobrar / Cotizaciones')),
      body: FutureBuilder<List<Quote>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final quotes = snap.data!;
          if (quotes.isEmpty) {
            return const EmptyState(
              icon: Icons.request_quote_outlined,
              title: 'Sin cotizaciones vigentes',
              hint: 'Arma un carrito en Venta y toca "Cotización" para '
                  'guardarlo aquí.',
            );
          }
          final theme = Theme.of(context);
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: quotes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final q = quotes[i];
              final expired =
                  q.expiresAt != null && q.expiresAt!.isBefore(DateTime.now());
              return SurfaceCard(
                onTap: () => _openDetail(q),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              StatusPill(q.folio),
                              const SizedBox(width: 6),
                              if (expired)
                                StatusPill('Vencida',
                                    color: theme.colorScheme.error),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            [
                              df.format(q.createdAt),
                              if (q.expiresAt != null && !expired)
                                'vence ${df.format(q.expiresAt!)}',
                            ].join('  ·  '),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    StatBlock(
                      label: 'Total',
                      value: money(q.totalCents),
                      size: 18,
                      alignEnd: true,
                    ),
                    Icon(Icons.chevron_right, color: theme.hintColor),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Renglón de cotización con nombre legible y si es un servicio.
class _LineView {
  const _LineView(this.line, this.desc, this.esServicio);
  final QuoteLine line;
  final String desc;
  final bool esServicio;
}
