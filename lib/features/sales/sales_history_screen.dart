import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../data/repositories/sales_repository.dart';
import '../../services/auth_controller.dart';
import 'pdf_actions.dart';
import 'ticket_service.dart';

/// Vender → **Ventas**: qué se vendió y cuándo, venta por venta.
///
/// Faltaba justo eso. El Balance da totales y rankings del periodo, y las
/// Devoluciones abren una venta **si te acuerdas del folio**; no había dónde ver
/// el ticket de las 11:40 con sus tres gorras. (Pedido del dueño, 20 ago 2026.)
///
/// Las **canceladas se muestran**, tachadas y marcadas: el dueño necesita ver
/// que esa venta existió y que se canceló, no que desapareció. Ninguna suma del
/// periodo las cuenta, igual que en los reportes.
/// Convierte un rango de **días inclusivos** (lo que devuelve el calendario) en
/// el corte `[desde, hasta)` que usan el repositorio y los reportes.
///
/// Los dos sentidos viven aquí porque el error de un día se cometió en ambos: la
/// lista terminaba un día antes, o mostraba uno de más. `test/rango_fechas_test`
/// los cuida.
({DateTime desde, DateTime hasta}) cortePorDias(DateTimeRange rango) {
  final desde =
      DateTime(rango.start.year, rango.start.month, rango.start.day);
  final hasta = DateTime(rango.end.year, rango.end.month, rango.end.day)
      .add(const Duration(days: 1));
  return (desde: desde, hasta: hasta);
}

/// El inverso: de un corte `[desde, hasta)` a los días inclusivos del
/// calendario. Se resta 1 ms y NO un día, porque los periodos del Balance
/// terminan en "ahora" y no a medianoche: restar un día se comía el día actual.
DateTimeRange diasInclusivos(DateTime desde, DateTime hasta) => DateTimeRange(
      start: desde,
      end: hasta.subtract(const Duration(milliseconds: 1)),
    );

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.rangoInicial, this.etiquetaInicial});

  /// Periodo con el que abre. Lo usa el Balance para entrar con el MISMO rango
  /// que el dueño está viendo: si mira el mes, quiere los tickets del mes.
  final DateTimeRange? rangoInicial;

  /// Cómo se llama ese periodo en el Balance ('Este mes', '90 días'…), para que
  /// la pastilla diga lo mismo en las dos pantallas.
  final String? etiquetaInicial;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _Periodo {
  const _Periodo(this.label, this.desde, this.hasta);
  final String label;
  final DateTime desde;
  final DateTime hasta;
}

class _Datos {
  const _Datos(this.ventas, this.nombres);
  final List<Sale> ventas;
  final Map<int, String> nombres;
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final SalesRepository _repo = SalesRepository(_db);

  late String _preset = widget.rangoInicial == null ? 'hoy' : 'custom';
  late DateTimeRange? _rango = widget.rangoInicial;

  /// Nombre heredado del Balance ('Este mes'). Se borra en cuanto el dueño
  /// elige otras fechas: si no, la pastilla seguiría diciendo 'Este mes' con un
  /// rango distinto.
  late String? _etiquetaHeredada = widget.etiquetaInicial;
  late Future<_Datos> _future = _cargar();
  String _busqueda = '';

  Profile get _actor => context.read<AuthController>().currentUser!;
  bool get _puedeCancelar => Permissions.canCancelSale(_actor.role);

  static const _presets = <(String, String)>[
    ('hoy', 'Hoy'),
    ('ayer', 'Ayer'),
    ('7d', '7 días'),
    ('30d', '30 días'),
    ('mes', 'Este mes'),
    ('mespasado', 'Mes pasado'),
    ('custom', 'Fechas…'),
  ];

  _Periodo get _periodo {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final f = DateFormat('dd/MM/yy');
    switch (_preset) {
      case 'ayer':
        final ayer = hoy.subtract(const Duration(days: 1));
        return _Periodo('Ayer', ayer, hoy);
      case '7d':
        return _Periodo('7 días', hoy.subtract(const Duration(days: 6)),
            hoy.add(const Duration(days: 1)));
      case '30d':
        return _Periodo('30 días', hoy.subtract(const Duration(days: 29)),
            hoy.add(const Duration(days: 1)));
      case 'mes':
        return _Periodo('Este mes', DateTime(ahora.year, ahora.month, 1),
            hoy.add(const Duration(days: 1)));
      case 'mespasado':
        return _Periodo('Mes pasado', DateTime(ahora.year, ahora.month - 1, 1),
            DateTime(ahora.year, ahora.month, 1));
      case 'custom':
        final r = _rango;
        if (r == null) return _Periodo('Hoy', hoy, hoy.add(const Duration(days: 1)));
        final corte = cortePorDias(r);
        return _Periodo(
            _etiquetaHeredada ?? '${f.format(r.start)}–${f.format(r.end)}',
            corte.desde,
            corte.hasta);
      default:
        return _Periodo('Hoy', hoy, hoy.add(const Duration(days: 1)));
    }
  }

  /// Elegir el periodo. 'custom' abre el calendario de rango; si el dueño lo
  /// cierra sin elegir, el filtro se queda como estaba (no se vacía la lista).
  Future<void> _elegirPeriodo(String slug) async {
    if (slug == 'custom') {
      final ahora = DateTime.now();
      final elegido = await showDateRangePicker(
        context: context,
        firstDate: DateTime(ahora.year - 3),
        lastDate: ahora,
        initialDateRange: _rango,
        helpText: 'Ventas entre…',
        saveText: 'Ver',
      );
      if (elegido == null) return;
      setState(() {
        _rango = elegido;
        _preset = 'custom';
        _etiquetaHeredada = null;
      });
    } else {
      setState(() => _preset = slug);
    }
    _recargar();
  }

  Future<_Datos> _cargar() async {
    final p = _periodo;
    final ventas = await _repo.history(desde: p.desde, hasta: p.hasta);
    final nombres = await _repo.profileNames();
    return _Datos(ventas, nombres);
  }

  void _recargar() => setState(() => _future = _cargar());

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------------------------------
  // Cancelar
  // --------------------------------------------------------------------------

  /// Cancelar NO borra la venta: la marca cancelada, regresa el inventario y
  /// deja el rastro. El folio se queda porque hay un ticket impreso con ese
  /// número y el corte de ese día tiene que seguir cuadrando.
  Future<void> _cancelar(Sale venta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Cancelar la venta ${venta.folio}'),
        content: Text(
            'Se cancela por ${money(venta.totalCents)} y las piezas regresan al '
            'inventario. La venta deja de contar en el corte y en los reportes, '
            'pero el folio se conserva —hay un ticket impreso con ese número— y '
            'queda registrado quién la canceló.\n\n¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar la venta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.cancelSale(
          actor: _actor, saleId: venta.id, reason: 'Cancelada desde Ventas');
      _toast('Venta ${venta.folio} cancelada');
      _recargar();
    } catch (e) {
      // Los estados que no se pueden cancelar (apartado, ya devuelta) explican
      // por dónde va el camino correcto: se muestra el mensaje tal cual.
      _toast(e is StateError ? e.message : '$e');
    }
  }

  Future<void> _reimprimir(Sale venta, Map<int, String> nombres) async {
    final lineas = await _repo.linesOf(venta.id);
    final pagos = await _repo.paymentsOf(venta.id);
    final cfg = await TicketConfig.load(_db);
    if (!mounted) return;
    await showDocumentActions(
      context,
      title: 'Ticket ${venta.folio}',
      filename: 'ticket_${venta.folio}',
      shareHint: 'Mandarlo por WhatsApp o volver a imprimirlo',
      build: (_) => TicketService.buildPdf(
        TicketData(
          folio: venta.folio,
          dateTime: venta.createdAt,
          cashierName: nombres[venta.cashierId] ?? '',
          lines: [
            for (final l in lineas)
              TicketLine(
                description: l.titulo,
                qty: l.qty,
                unitPriceCents: l.unitPriceCents,
                lineTotalCents: l.lineTotalCents,
              )
          ],
          subtotalCents: venta.subtotalCents,
          discountCents: venta.discountCents,
          taxCents: venta.taxCents,
          totalCents: venta.totalCents,
          payments: [
            for (final p in pagos) (_metodo(p.method), p.amountCents)
          ],
          changeCents: 0,
          gift: false,
        ),
        config: cfg,
      ),
    );
  }

  static String _metodo(PaymentMethod m) => switch (m) {
        PaymentMethod.cash => 'Efectivo',
        PaymentMethod.card => 'Tarjeta',
        PaymentMethod.transfer => 'Transferencia',
        PaymentMethod.creditNote => 'Nota de crédito',
        PaymentMethod.giftCard => 'Tarjeta de regalo',
      };

  static (String, Color?) _estado(Sale s, ThemeData theme) => switch (s.status) {
        SaleStatus.completed => ('Cobrada', AppColors.success),
        SaleStatus.cancelled => ('Cancelada', theme.colorScheme.error),
        SaleStatus.returned => ('Devuelta', theme.colorScheme.error),
        SaleStatus.partialReturn => ('Devuelta en parte', null),
        SaleStatus.layaway => ('Apartado', null),
      };

  // --------------------------------------------------------------------------
  // Detalle
  // --------------------------------------------------------------------------

  Future<void> _abrir(Sale venta, Map<int, String> nombres) async {
    final lineas = await _repo.linesOf(venta.id);
    final pagos = await _repo.paymentsOf(venta.id);
    if (!mounted) return;
    final theme = Theme.of(context);
    // Sin locale: la app no llama a `initializeDateFormatting`, así que pedir
    // 'es_MX' lanza LocaleDataException en tiempo de ejecución. Mismo formato
    // que usan las notas de servicio.
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final (etiqueta, color) = _estado(venta, theme);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (hoja) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Venta ${venta.folio}',
                          style: theme.textTheme.titleLarge),
                    ),
                    StatusPill(etiqueta, color: color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(df.format(venta.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Divider(height: 20),

                // Lo que se vendió: la pregunta que originó esta pantalla.
                for (final l in lineas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text('${l.qty}×',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.titulo),
                              if (l.discountCents > 0)
                                Text('descuento ${money(l.discountCents)}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.error)),
                            ],
                          ),
                        ),
                        Text(money(l.lineTotalCents),
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),

                const Divider(height: 20),
                if (venta.discountCents > 0)
                  _renglonTotal('Descuento', '−${money(venta.discountCents)}'),
                for (final p in pagos)
                  _renglonTotal(_metodo(p.method), money(p.amountCents)),
                const SizedBox(height: 6),
                StatBlock(
                    label: 'Total', value: money(venta.totalCents), size: 26),
                const SizedBox(height: 4),
                Text(
                  'Cobró: ${nombres[venta.cashierId] ?? '—'}'
                  '${venta.salespersonId != null && venta.salespersonId != venta.cashierId ? ' · Vendió: ${nombres[venta.salespersonId] ?? '—'}' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                if (venta.notes != null && venta.notes!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${venta.notes}',
                      style: theme.textTheme.bodySmall),
                ],

                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(hoja).pop();
                    _reimprimir(venta, nombres);
                  },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Reimprimir / compartir ticket'),
                ),
                if (venta.status == SaleStatus.completed && _puedeCancelar) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: () {
                      Navigator.of(hoja).pop();
                      _cancelar(venta);
                    },
                    icon: const Icon(Icons.block),
                    label: const Text('Cancelar esta venta'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _renglonTotal(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(etiqueta, style: const TextStyle(fontSize: 13)),
            Text(valor,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  // --------------------------------------------------------------------------
  // Vista
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ventas')),
      body: FutureBuilder<_Datos>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final datos = snap.data!;
          final q = _busqueda.trim().toLowerCase();
          final ventas = q.isEmpty
              ? datos.ventas
              : datos.ventas
                  .where((v) => v.folio.toLowerCase().contains(q))
                  .toList();

          // El resumen NO cuenta canceladas, igual que los reportes.
          final vivas =
              ventas.where((v) => v.status != SaleStatus.cancelled).toList();
          final total =
              vivas.fold<int>(0, (a, v) => a + v.totalCents);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: FilterChipsRow(
                  labels: [for (final p in _presets) p.$2],
                  selectedIndex: _presets.indexWhere((p) => p.$1 == _preset),
                  onSelected: (i) => _elegirPeriodo(_presets[i].$1),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SearchField(
                  hint: 'Buscar por folio…',
                  onChanged: (v) => setState(() => _busqueda = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: SurfaceCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${vivas.length} venta'
                          '${vivas.length == 1 ? '' : 's'} · ${_periodo.label}'),
                      Text(money(total),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ventas.isEmpty
                    ? const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Sin ventas en este periodo',
                        hint: 'Cambia el periodo de arriba, o cobra algo en '
                            'Vender y aquí aparece con su hora.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: ventas.length,
                        itemBuilder: (_, i) =>
                            _renglon(ventas[i], datos.nombres),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _renglon(Sale v, Map<int, String> nombres) {
    final theme = Theme.of(context);
    final hora = DateFormat('HH:mm').format(v.createdAt);
    final dia = DateFormat('dd/MM').format(v.createdAt);
    final cancelada = v.status == SaleStatus.cancelled;
    final (etiqueta, color) = _estado(v, theme);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        onTap: () => _abrir(v, nombres),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(hora,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                Text(dia,
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(v.folio,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(etiqueta, color: color),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(nombres[v.cashierId] ?? '—',
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(money(v.totalCents),
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    decoration: cancelada ? TextDecoration.lineThrough : null,
                    color: cancelada ? theme.hintColor : null)),
            Icon(Icons.chevron_right, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}
