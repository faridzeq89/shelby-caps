import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';

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
      body: const Center(
        child: Text(
          'Panel de administración\n(catálogo, usuarios y reportes llegan en fases próximas)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
