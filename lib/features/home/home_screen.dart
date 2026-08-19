import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../data/local/database.dart';
import '../../services/auth_controller.dart';
import '../../services/motd_settings.dart';
import '../../services/quick_menu.dart';
import '../../services/sale_handoff.dart';
import '../catalog/catalog_home_screen.dart';
import '../motd/daily_motd.dart';
import '../reports/reports_screen.dart';
import '../sales/sale_screen.dart';
import 'app_drawer.dart';
import 'inicio_screen.dart';
import 'quick_destinations.dart';

/// Shell principal estilo Treinta: header carbón con **hamburguesa** (menú con
/// todas las funciones), **bottom-nav** con las 4 más usadas (Inicio · Vender ·
/// Inventario · Balance) y un IndexedStack que conserva el estado de cada
/// pestaña (p. ej. el carrito).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  final _inicioKey = GlobalKey<InicioScreenState>();
  final _saleKey = GlobalKey<SaleScreenState>();
  // Época para reconstruir Inventario/Balance al volver (datos frescos).
  int _invEpoch = 0;
  int _balEpoch = 0;

  SaleHandoff? _handoff;

  @override
  void initState() {
    super.initState();
    // La primera vez de cada día (en este aparato) se saluda con una frase
    // motivadora. Post-frame para no mostrar un diálogo a medio construir.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowMotd());
  }

  Future<void> _maybeShowMotd() async {
    // El saludo del día es de la versión web (el mostrador del cliente). En la
    // app instalada no aplica; además así no estorba a las pruebas de widget.
    if (!kIsWeb) return;
    final motd = MotdSettings(context.read<AppDatabase>());
    if (!await motd.shouldShowToday()) return;
    // Se marca ANTES de mostrar: si cierran la pestaña con el mensaje abierto,
    // igual cuenta como visto de hoy y no reaparece al reabrir.
    await motd.markShownToday();
    if (!mounted) return;
    await showDailyMotd(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cuando alguien manda una cotización a venta (desde el menú, Inicio o la
    // propia Venta), el shell salta a la pestaña Vender para que se vea cargada.
    final handoff = context.read<SaleHandoff>();
    if (identical(handoff, _handoff)) return;
    _handoff?.removeListener(_onHandoff);
    _handoff = handoff..addListener(_onHandoff);
  }

  void _onHandoff() {
    if (!mounted || !(_handoff?.hasPending ?? false)) return;
    _goTab(1);
  }

  @override
  void dispose() {
    _handoff?.removeListener(_onHandoff);
    super.dispose();
  }

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  /// Barra de abajo armada con lo que el dueño eligió. Es propia y no un
  /// `NavigationBar` porque este tiene que aceptar cualquier cantidad de
  /// botones, esconder las etiquetas de 5 en adelante, y convivir con atajos
  /// que abren pantallas en vez de cambiar de pestaña (esos nunca se marcan
  /// como seleccionados).
  Widget _quickBar() {
    final theme = Theme.of(context);
    final isAdmin = context.watch<AuthController>().isAdmin;
    final menu = context.watch<QuickMenu>();

    final items = [
      for (final id in menu.ids)
        if (destinationById(id) case final d?)
          if (!d.adminOnly || isAdmin) d,
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Material(
      color: theme.cardColor,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: Container(
          height: menu.showLabels ? 64 : 56,
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              for (final d in items)
                Expanded(
                    child: _quickButton(
                        d, menu.showLabels, menu.labelSize)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickButton(QuickDestination d, bool showLabel, double labelSize) {
    final theme = Theme.of(context);
    // Solo las pestañas se marcan: un atajo no es un lugar donde uno "está".
    final selected = d.isTab && d.tabIndex == _index;
    final color = selected ? AppColors.accent : theme.hintColor;

    return InkWell(
      onTap: () {
        if (d.isTab) {
          // Vender es la única pestaña que pregunta primero qué se va a hacer.
          if (d.tabIndex == 1) {
            _goVender();
          } else {
            _goTab(d.tabIndex!);
          }
        } else {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => d.builder!()));
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.brand.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Icon(selected ? d.selectedIcon : d.icon,
                size: 22, color: color),
          ),
          if (showLabel) ...[
            const SizedBox(height: 3),
            // `scaleDown` en vez de recortar con "…": en una pantalla angosta
            // "Devoluciones" se encoge un poco pero se sigue leyendo entero,
            // que es mejor que un "Devolucion…" que no dice nada.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  d.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: labelSize,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? AppColors.accent : theme.hintColor,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Ir a Vender preguntando primero **qué se va a hacer**: cobrar o cotizar.
  /// Es lo que el cliente ya conocía de Treinta.
  ///
  /// La pregunta sale **solo con el carrito vacío**. Con un carrito a medias
  /// se entra directo: "Vender" es una pestaña que conserva su estado, y
  /// preguntar cada vez que se vuelve a ella sería estorbar a media venta.
  /// Cerrar la hoja sin elegir no mueve de donde se está.
  Future<void> _goVender() async {
    final sale = _saleKey.currentState;
    if (sale != null && sale.hasCart) {
      _goTab(1);
      return;
    }
    final cotiza = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _NuevaVentaSheet(),
    );
    if (cotiza == null || !mounted) return;
    _goTab(1);
    _saleKey.currentState?.setQuoteMode(cotiza);
  }

  void _goTab(int i) {
    setState(() {
      _index = i;
      if (i == 0) _inicioKey.currentState?.reload();
      if (i == 1) _saleKey.currentState?.reloadCatalog();
      if (i == 2) _invEpoch++;
      if (i == 3) _balEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      InicioScreen(
        key: _inicioKey,
        onMenu: _openMenu,
        onRegistrarVenta: _goVender,
        onGoBalance: () => _goTab(3),
      ),
      SaleScreen(key: _saleKey, onMenu: _openMenu),
      CatalogHomeScreen(key: ValueKey('inv-$_invEpoch'), onMenu: _openMenu),
      ReportsScreen(key: ValueKey('bal-$_balEpoch'), onMenu: _openMenu),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(onGoTab: _goTab),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _quickBar(),
    );
  }
}

/// Hoja "Nueva venta": cobrar o cotizar, elegido **antes** de armar el
/// carrito. El cliente venía de otra app que preguntaba así y no encontraba
/// dónde cotizar.
///
/// No lleva "Venta libre" (registrar un ingreso sin tocar productos): aquí el
/// inventario es un libro mayor y una venta sin líneas dejaría el stock
/// diciendo una cosa y la caja otra.
///
/// Devuelve `true` para cotización, `false` para venta, `null` si se cerró sin
/// elegir — en ese caso quien la abrió no se mueve de donde está.
class _NuevaVentaSheet extends StatelessWidget {
  const _NuevaVentaSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Con scroll: en una pantalla corta (teléfono acostado) la hoja no cabe
    // y sin esto desborda en vez de dejarse recorrer.
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nueva venta', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Elige qué vas a hacer. Puedes cambiar de opinión después, con '
              'el carrito ya armado.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _opcion(
              context,
              icon: Icons.shopping_basket_outlined,
              title: 'Venta de productos',
              hint: 'Arma el carrito con los productos y cóbralo.',
              onTap: () => Navigator.of(context).pop(false),
            ),
            const SizedBox(height: 10),
            _opcion(
              context,
              icon: Icons.request_quote_outlined,
              title: 'Cotización',
              hint: 'Arma el carrito y guárdalo para compartirlo con el '
                  'cliente, sin cobrar ni mover inventario.',
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _opcion(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String hint,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(icon, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(hint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: theme.hintColor),
        ],
      ),
    );
  }
}
