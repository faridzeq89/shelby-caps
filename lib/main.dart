import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'data/local/open_db.dart';
import 'data/seed.dart';
import 'services/auth_controller.dart';
import 'services/cloud_backup_service.dart';
import 'services/palette_settings.dart';
import 'services/quick_menu.dart';
import 'services/session_settings.dart';
import 'services/tax_settings.dart';

/// Proyecto Supabase de Shelby Caps, empaquetado como último recurso para que
/// el POS **web conecte solo en cualquier dispositivo** (el cliente no teclea
/// nada). La llave anon es **PÚBLICA** por diseño: rol `anon`, solo lectura;
/// las escrituras las bloquea RLS y la publicación usa un secreto aparte. Es la
/// misma que ya va, commiteada, en `web-catalogo/config.js`. **NUNCA** poner
/// aquí `service_role` ni el secreto de publicación.
///
/// (El `.env` no sirve en web: Flutter no registra en el AssetManifest los
/// archivos que empiezan con ".", así que `rootBundle` no lo encuentra.)
const _fallbackSupabaseUrl = 'https://phyjseekbyitlntmjwwe.supabase.co';
const _fallbackSupabaseAnon =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBoeWpzZWVrYnlpdGxudG1qd3dlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY0MDg4MzMsImV4cCI6MjEwMTk4NDgzM30.0xbMKEAN6cmzua3YPeHwOFx5rAapMcGHOk8LJrooY20';

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
  final paleta = PaletteSettings(db);
  await paleta.load();
  final quick = QuickMenu(db);
  await quick.load();
  final tax = TaxSettings(db);
  await tax.load();
  final session = SessionSettings(db);
  await session.load();
  // Entra sin PIN solo si el dueño lo dejó configurado y ese perfil sigue
  // activo; si no, la app abre en la pantalla de PIN de siempre.
  final directo = await session.profileToAutoLogin();
  if (directo != null) auth.loginAs(directo);
  runApp(BoutiquePosApp(
      auth: auth,
      db: db,
      backup: backup,
      tax: tax,
      quickMenu: quick,
      paleta: paleta,
      session: session));
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
    // Último recurso: llaves públicas empaquetadas. Garantiza que el POS web
    // conecte solo aunque no haya config en la app ni `.env` cargable.
    url ??= _fallbackSupabaseUrl;
    key ??= _fallbackSupabaseAnon;
    if (url.isEmpty || key.isEmpty) return false;
    // Llave anon (JWT legacy). El parámetro anonKey sigue funcionando para estas.
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: key);
    return true;
  } catch (_) {
    return false;
  }
}
