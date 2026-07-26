import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/change_pin_screen.dart';
import 'features/auth/pin_login_screen.dart';
import 'features/home/home_screen.dart';
import 'services/auth_controller.dart';
import 'services/cloud_backup_service.dart';

/// Raíz de la app. Recibe la base y un [AuthController] ya sembrado para poder
/// inyectar una base en memoria desde los tests.
class BoutiquePosApp extends StatelessWidget {
  const BoutiquePosApp(
      {super.key, required this.auth, required this.db, this.backup});

  final AuthController auth;
  final AppDatabase db;
  final CloudBackupService? backup;

  @override
  Widget build(BuildContext context) {
    final backupSvc = backup ?? CloudBackupService(db, enabled: false);
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider<CloudBackupService>.value(value: backupSvc),
      ],
      child: MaterialApp(
        title: 'Montana Boutique',
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
