import 'package:flutter/material.dart';

import '../catalog/catalog_home_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sale_screen.dart';
import 'app_drawer.dart';
import 'inicio_screen.dart';

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

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Vender',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Balance',
          ),
        ],
      ),
    );
  }
}
