import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';
import '../catalog/catalog_home_screen.dart';
import '../inventory/inventory_home_screen.dart';
import '../reports/reports_screen.dart';
import 'cloud_backup_screen.dart';

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
          const Card(
            child: ListTile(
              leading: Icon(Icons.groups_outlined),
              title: Text('Usuarios'),
              subtitle: Text('Próxima fase'),
              enabled: false,
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
        ],
      ),
    );
  }
}
