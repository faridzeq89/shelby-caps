import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';
import 'pin_pad.dart';

/// Pantalla de acceso: se escribe el PIN y, si coincide con un usuario activo,
/// entra al sistema con su rol.
class PinLoginScreen extends StatelessWidget {
  const PinLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PinPad(
            title: 'POS Boutique',
            subtitle: 'Ingresa tu PIN para comenzar',
            onSubmit: (pin) async {
              final ok = await auth.loginWithPin(pin);
              return ok ? null : 'PIN incorrecto';
            },
          ),
        ),
      ),
    );
  }
}
