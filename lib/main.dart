import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'data/local/open_db.dart';
import 'data/seed.dart';
import 'services/auth_controller.dart';
import 'services/cloud_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  final cloudEnabled = await _initSupabase(db);
  final auth = AuthController(db);
  await auth.ensureSeedAdmin();
  await SeedService(db).run();
  // En el navegador no hay archivo de base que subir, así que el respaldo por
  // archivo queda apagado y la pantalla lo dice en vez de fallar a medias.
  final backup =
      CloudBackupService(db, enabled: cloudEnabled && supportsFileBackup);
  // Install existente (ya con ventas) reclama solo para seguir respaldando tras
  // actualizar; una tablet nueva queda sin reclamar hasta que el usuario decida.
  await backup.autoClaimIfHasData();
  backup.startPeriodic();
  runApp(BoutiquePosApp(auth: auth, db: db, backup: backup));
}

/// Lee un valor de `app_settings`, o null si no existe / está vacío.
Future<String?> _setting(AppDatabase db, String key) async {
  final row = await (db.select(db.appSettings)..where((t) => t.key.equals(key)))
      .getSingleOrNull();
  final v = row?.value.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Inicializa Supabase. Prioridad: **configuración guardada en la app**
/// (Admin → Respaldo → Configurar conexión, en `app_settings`), que permite
/// conectar sin recompilar; si no hay, cae al `.env` empaquetado al compilar.
/// Si no hay ninguna, la app sigue 100% local (respaldo deshabilitado).
Future<bool> _initSupabase(AppDatabase db) async {
  try {
    String? url = await _setting(db, 'supabase_url');
    String? key = await _setting(db, 'supabase_anon');
    if (url == null || key == null) {
      try {
        await dotenv.load(fileName: '.env');
        final env = (dotenv.maybeGet('SUPABASE_ENV') ?? 'dev').toUpperCase();
        url ??= (dotenv.maybeGet('SUPABASE_URL_$env')?.trim().isNotEmpty ?? false)
            ? dotenv.maybeGet('SUPABASE_URL_$env')!.trim()
            : null;
        key ??= (dotenv.maybeGet('SUPABASE_ANON_$env')?.trim().isNotEmpty ?? false)
            ? dotenv.maybeGet('SUPABASE_ANON_$env')!.trim()
            : null;
      } catch (_) {
        // Sin .env empaquetado: no pasa nada, seguimos con lo que haya.
      }
    }
    if (url == null || key == null) return false;
    // Llave anon (JWT legacy). El parámetro anonKey sigue funcionando para estas.
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: key);
    return true;
  } catch (_) {
    return false;
  }
}
