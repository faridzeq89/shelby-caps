import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'data/local/database.dart';
import 'data/seed.dart';
import 'services/auth_controller.dart';
import 'services/cloud_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cloudEnabled = await _initSupabase();
  final db = AppDatabase();
  final auth = AuthController(db);
  await auth.ensureSeedAdmin();
  await SeedService(db).run();
  final backup = CloudBackupService(db, enabled: cloudEnabled)..startPeriodic();
  runApp(BoutiquePosApp(auth: auth, db: db, backup: backup));
}

/// Inicializa Supabase desde `.env`. Si no hay `.env` o falla, la app sigue
/// funcionando 100% local (respaldo deshabilitado).
Future<bool> _initSupabase() async {
  try {
    await dotenv.load(fileName: '.env');
    final env = (dotenv.maybeGet('SUPABASE_ENV') ?? 'dev').toUpperCase();
    final url = dotenv.maybeGet('SUPABASE_URL_$env') ?? '';
    final key = dotenv.maybeGet('SUPABASE_ANON_$env') ?? '';
    if (url.isEmpty || key.isEmpty) return false;
    // Llave anon (JWT legacy). El parámetro anonKey sigue funcionando para estas.
    // ignore: deprecated_member_use
    await Supabase.initialize(url: url, anonKey: key);
    return true;
  } catch (_) {
    return false;
  }
}
