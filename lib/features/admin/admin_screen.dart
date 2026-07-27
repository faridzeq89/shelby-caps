import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/demo_seed.dart';
import '../../data/local/database.dart';
import '../../services/auth_controller.dart';
import '../catalog/catalog_home_screen.dart';
import '../customers/customers_screen.dart';
import '../inventory/inventory_home_screen.dart';
import '../reports/reports_screen.dart';
import 'cloud_backup_screen.dart';
import 'reconciliation_screen.dart';
import 'users_screen.dart';

/// Panel de administración. Solo para rol admin: aunque se navegue directo,
/// un no-admin ve "Acceso denegado" (la puerta se cierra aquí, no solo
/// escondiendo el botón).
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

    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Catálogo'),
              subtitle: const Text('Productos, variantes, códigos y etiquetas'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CatalogHomeScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Inventario'),
              subtitle: const Text('Recepción, ajustes, conteo y stock bajo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InventoryHomeScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Respaldo en la nube'),
              subtitle: const Text('Respaldar / restaurar (Supabase)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CloudBackupScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Reconciliación'),
              subtitle: const Text('Stock negativo, folios, pagos que no cuadran'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReconciliationScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Usuarios'),
              subtitle: const Text('Crear cajeros/gerentes, PIN, activar'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UsersScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('Clientes'),
              subtitle: const Text('Ficha, historial de compras y totales'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustomersScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bar_chart_outlined),
              title: const Text('Reportes'),
              subtitle: const Text('Ventas, margen, inventario muerto, export'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Cargar catálogo de prueba'),
              subtitle: const Text('100 productos de demo con fotos y stock'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _loadDemoCatalog(context),
            ),
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
    messenger.showSnackBar(const SnackBar(
        content: Text('Cargando catálogo de prueba…')));
    try {
      final n = await DemoSeedService(db).load(count: 100);
      messenger.showSnackBar(
          SnackBar(content: Text('$n productos de prueba cargados')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
