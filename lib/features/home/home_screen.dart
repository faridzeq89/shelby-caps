import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';
import '../admin/admin_screen.dart';
import '../sales/cash_session_screen.dart';
import '../sales/sale_screen.dart';

/// Shell principal con menú inferior estilo app. Las pestañas viven en un
/// IndexedStack para conservar su estado (p. ej. el carrito) al cambiar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  // Al volver a una pestaña de datos se le cambia la "época" (key) para que se
  // reconstruya y recargue (ventas/devoluciones recientes aparecen al instante).
  int _corteEpoch = 0;
  int _adminEpoch = 0;
  // La venta NO se reconstruye (conserva el carrito); se recarga en sitio vía
  // esta llave al volver a la pestaña (p. ej. tras cargar catálogo de prueba).
  final _saleKey = GlobalKey<SaleScreenState>();

  Future<void> _confirmLogout(AuthController auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Salir de tu sesión?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true) auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isAdmin = auth.isAdmin;

    final pages = <Widget>[
      SaleScreen(key: _saleKey),
      CashSessionScreen(key: ValueKey('corte-$_corteEpoch')),
      if (isAdmin) AdminScreen(key: ValueKey('admin-$_adminEpoch')),
    ];
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.point_of_sale_outlined),
        selectedIcon: Icon(Icons.point_of_sale),
        label: 'Vender',
      ),
      const NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: 'Corte',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: 'Admin',
        ),
      const NavigationDestination(
        icon: Icon(Icons.logout),
        label: 'Salir',
      ),
    ];
    final logoutIndex = pages.length;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == logoutIndex) {
            _confirmLogout(auth);
          } else {
            setState(() {
              // Recarga la pestaña de datos al entrar.
              if (i == 0) _saleKey.currentState?.reloadCatalog();
              if (i == 1) _corteEpoch++;
              if (i == 2) _adminEpoch++;
              _index = i;
            });
          }
        },
        destinations: destinations,
      ),
    );
  }
}
