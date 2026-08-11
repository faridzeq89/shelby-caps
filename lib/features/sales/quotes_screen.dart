import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/local/database.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/customer_repository.dart';
import '../../data/repositories/quote_repository.dart';
import '../../services/auth_controller.dart';
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

  String _money(int c) => '\$${(c / 100).toStringAsFixed(2)}';

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

  Future<void> _openDetail(Quote q) async {
    final lines = await _repo.linesOf(q.id);
    final pdfLines = await _pdfLines(lines);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cotización ${q.folio}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...pdfLines.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${l.qty} × ${l.description}')),
                        Text(_money(l.lineTotalCents)),
                      ],
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total', style: Theme.of(context).textTheme.titleMedium),
                  Text(_money(q.totalCents),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  Navigator.of(context).pop(q); // pasar a venta
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
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yy');
    return Scaffold(
      appBar: AppBar(title: const Text('Cotizaciones')),
      body: FutureBuilder<List<Quote>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final quotes = snap.data!;
          if (quotes.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sin cotizaciones vigentes.\nArma un carrito en Venta y toca '
                  '"Guardar cotización".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: quotes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final q = quotes[i];
              final expired =
                  q.expiresAt != null && q.expiresAt!.isBefore(DateTime.now());
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
                title: Text('${q.folio}  ·  ${_money(q.totalCents)}'),
                subtitle: Text([
                  df.format(q.createdAt),
                  if (q.expiresAt != null)
                    expired
                        ? 'vencida'
                        : 'vence ${df.format(q.expiresAt!)}',
                ].join('  ·  ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openDetail(q),
              );
            },
          );
        },
      ),
    );
  }
}
