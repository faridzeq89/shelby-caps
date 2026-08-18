import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'data/local/database.dart';
import 'features/auth/change_pin_screen.dart';
import 'features/auth/pin_login_screen.dart';
import 'features/home/home_screen.dart';
import 'services/auth_controller.dart';
import 'services/catalog_sync_service.dart';
import 'services/cloud_backup_service.dart';
import 'services/palette_settings.dart';
import 'services/quick_menu.dart';
import 'services/sale_handoff.dart';
import 'services/session_settings.dart';
import 'services/tax_settings.dart';

/// Raíz de la app. Recibe la base y un [AuthController] ya sembrado para poder
/// inyectar una base en memoria desde los tests.
class BoutiquePosApp extends StatelessWidget {
  const BoutiquePosApp(
      {super.key,
      required this.auth,
      required this.db,
      this.backup,
      this.tax,
      this.quickMenu,
      this.paleta,
      this.session});

  final AuthController auth;
  final AppDatabase db;
  final CloudBackupService? backup;

  /// Ajuste de IVA ya cargado. Los tests pueden omitirlo: por defecto queda
  /// apagado, que es como opera este negocio.
  final TaxSettings? tax;

  /// Botones de la barra de abajo ya cargados; sin él salen los de fábrica.
  final QuickMenu? quickMenu;

  /// Colores elegidos por el dueño; sin ellos sale la paleta de fábrica.
  final PaletteSettings? paleta;

  /// Acceso directo (entrar sin PIN). Sin él queda apagado, que es lo de
  /// fábrica: siempre se pide el PIN.
  final SessionSettings? session;

  @override
  Widget build(BuildContext context) {
    final backupSvc = backup ?? CloudBackupService(db, enabled: false);
    final taxSvc = tax ?? TaxSettings(db);
    final quickSvc = quickMenu ?? QuickMenu(db);
    final paletaSvc = paleta ?? PaletteSettings(db);
    final sessionSvc = session ?? SessionSettings(db);
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider<CloudBackupService>.value(value: backupSvc),
        // Una sola instancia: el retraso antes de publicar vive en ella, y con
        // instancias sueltas cada pantalla tendría su propio temporizador.
        Provider<CatalogSyncService>(
          create: (_) => CatalogSyncService(db),
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProvider<SaleHandoff>(create: (_) => SaleHandoff()),
        ChangeNotifierProvider<TaxSettings>.value(value: taxSvc),
        ChangeNotifierProvider<QuickMenu>.value(value: quickSvc),
        ChangeNotifierProvider<PaletteSettings>.value(value: paletaSvc),
        ChangeNotifierProvider<SessionSettings>.value(value: sessionSvc),
      ],
      // El tema se reconstruye al cambiar de color: `buildAppTheme()` lee la
      // paleta ya aplicada, y el `watch` es lo que dispara el repintado.
      child: Consumer<PaletteSettings>(
        builder: (context, _, _) => MaterialApp(
          title: 'SHELBY CAPS',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const _RootGate(),
        ),
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
