import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dashboard_tile.dart';
import '../../data/demo_seed.dart';
import '../../data/local/database.dart';
import '../../services/auth_controller.dart';
import '../catalog/catalog_home_screen.dart';
import '../customers/customers_screen.dart';
import '../inventory/inventory_home_screen.dart';
import '../reports/reports_screen.dart';
import 'cloud_backup_screen.dart';
import 'loyalty_config_screen.dart';
import 'reconciliation_screen.dart';
import 'users_screen.dart';

/// Una entrada del panel de administración.
class _AdminItem {
  const _AdminItem(this.icon, this.title, this.subtitle, this.color, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final void Function(BuildContext) onTap;
}

/// Panel de administración en rejilla (dashboard). Solo para rol admin.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthController, bool>((a) => a.isAdmin);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administración')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              const Text('Acceso denegado', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              const Text('Necesitas rol de administrador.'),
            ],
          ),
        ),
      );
    }

    void go(BuildContext c, Widget screen) =>
        Navigator.of(c).push(MaterialPageRoute(builder: (_) => screen));

    final items = <_AdminItem>[
      _AdminItem(Icons.inventory_2_outlined, 'Catálogo',
          'Productos, variantes y etiquetas', Colors.indigo,
          (c) => go(c, const CatalogHomeScreen())),
      _AdminItem(Icons.inventory_outlined, 'Inventario',
          'Recepción, ajustes, conteo', Colors.teal,
          (c) => go(c, const InventoryHomeScreen())),
      _AdminItem(Icons.people_alt_outlined, 'Clientes',
          'Fichas, historial y totales', Colors.blue,
          (c) => go(c, const CustomersScreen())),
      _AdminItem(Icons.stars_outlined, 'Programa de puntos',
          'Reglas de lealtad', Colors.amber.shade800,
          (c) => go(c, const LoyaltyConfigScreen())),
      _AdminItem(Icons.bar_chart_outlined, 'Reportes',
          'Ventas, margen, recomendaciones', Colors.deepPurple,
          (c) => go(c, const ReportsScreen())),
      _AdminItem(Icons.groups_outlined, 'Usuarios',
          'Cajeros, gerentes y PIN', Colors.brown,
          (c) => go(c, const UsersScreen())),
      _AdminItem(Icons.cloud_outlined, 'Respaldo',
          'Respaldar / restaurar (nube)', Colors.cyan.shade700,
          (c) => go(c, const CloudBackupScreen())),
      _AdminItem(Icons.rule, 'Reconciliación',
          'Salud de datos', Colors.blueGrey,
          (c) => go(c, const ReconciliationScreen())),
      _AdminItem(Icons.auto_awesome_outlined, 'Catálogo de prueba',
          '100 productos demo', Colors.pink.shade400, _loadDemoCatalog),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: DashboardGrid(
        children: [
          for (final it in items)
            DashboardTile(
              icon: it.icon,
              title: it.title,
              subtitle: it.subtitle,
              color: it.color,
              onTap: () => it.onTap(context),
            ),
        ],
      ),
    );
  }

  Future<void> _loadDemoCatalog(BuildContext context) async {
    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cargar catálogo de prueba'),
        content: const Text(
            'Agrega 100 productos de demostración (con fotos y stock) para '
            'probar la app. Puedes borrarlos después. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cargar')),
        ],
      ),
    );
    if (ok != true) return;
    messenger.showSnackBar(
        const SnackBar(content: Text('Cargando catálogo de prueba…')));
    try {
      final n = await DemoSeedService(db).load(count: 100);
      messenger.showSnackBar(
          SnackBar(content: Text('$n productos de prueba cargados')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
