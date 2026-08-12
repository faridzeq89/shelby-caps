import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/auth_controller.dart';
import '../../services/quick_menu.dart';
import '../../services/sale_handoff.dart';
import '../catalog/catalog_home_screen.dart';
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
          _goTab(d.tabIndex!);
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
        onRegistrarVenta: () => _goTab(1),
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
