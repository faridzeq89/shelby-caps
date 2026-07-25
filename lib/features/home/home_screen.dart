import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/roles.dart';
import '../../services/auth_controller.dart';
import '../admin/admin_screen.dart';
import '../sales/sale_screen.dart';

/// Pantalla principal tras el login. Saluda al usuario con su rol y, solo para
/// admin, ofrece la entrada al panel de administración. El punto de venta real
/// llega en la Fase 4.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.currentUser!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Boutique'),
        actions: [
          IconButton(
            onPressed: auth.logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Hola, ${user.name}',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Chip(
              avatar: const Icon(Icons.badge_outlined, size: 20),
              label: Text(user.role.label),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SaleScreen()),
              ),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Vender'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(240, 72),
                textStyle:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            if (auth.isAdmin) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminScreen()),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('Administración'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
