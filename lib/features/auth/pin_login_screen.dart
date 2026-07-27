import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_controller.dart';
import 'pin_pad.dart';

/// Pantalla de acceso: logo + nombre, se escribe el PIN y, si coincide con un
/// usuario activo, entra al sistema con su rol.
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
            logo: Container(
              width: 104,
              height: 104,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Image.asset('assets/icono-app.png', fit: BoxFit.cover),
            ),
            title: 'Montana Boutique',
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
