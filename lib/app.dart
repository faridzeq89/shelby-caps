import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'features/auth/change_pin_screen.dart';
import 'features/auth/pin_login_screen.dart';
import 'features/home/home_screen.dart';
import 'services/auth_controller.dart';

/// Raíz de la app. Recibe un [AuthController] ya sembrado para poder inyectar
/// una base en memoria desde los tests.
class BoutiquePosApp extends StatelessWidget {
  const BoutiquePosApp({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: auth,
      child: MaterialApp(
        title: 'POS Boutique',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _RootGate(),
      ),
    );
  }
}

/// Decide qué pantalla mostrar según el estado de sesión.
class _RootGate extends StatelessWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (!auth.isLoggedIn) return const PinLoginScreen();
    if (auth.mustChangePin) return const ChangePinScreen();
    return const HomeScreen();
  }
}
