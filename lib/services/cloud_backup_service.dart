import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';

enum SyncState { disabled, idle, syncing, ok, error }

/// Respaldo del archivo completo de la base a Supabase Storage. Local-first: la
/// tablet es la verdad; esto es la red de seguridad. Ruta fija (single-tenant),
/// así una tablet nueva puede restaurar el último respaldo.
class CloudBackupService extends ChangeNotifier {
  CloudBackupService(this._db, {required this.enabled}) {
    state = enabled ? SyncState.idle : SyncState.disabled;
  }

  final AppDatabase _db;
  final bool enabled;

  static const _bucket = 'backups';
  static const _object = 'boutique.sqlite';

  SyncState state = SyncState.disabled;
  DateTime? lastBackupAt;
  String? lastError;
  Timer? _timer;

  SupabaseClient get _client => Supabase.instance.client;

  /// Arranca el respaldo periódico (cada 15 min) además del que ocurre tras
  /// cada venta.
  void startPeriodic() {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => backupNow());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Sube una foto consistente de la base. No lanza: reporta el estado.
  Future<void> backupNow() async {
    if (!enabled || state == SyncState.syncing) return;
    state = SyncState.syncing;
    notifyListeners();
    try {
      final bytes = await _snapshot();
      await _client.storage.from(_bucket).uploadBinary(
            _object,
            bytes,
            fileOptions: const FileOptions(
                upsert: true, contentType: 'application/octet-stream'),
          );
      lastBackupAt = DateTime.now();
      lastError = null;
      state = SyncState.ok;
    } catch (e) {
      lastError = '$e';
      state = SyncState.error;
    }
    notifyListeners();
  }

  /// Dispara un respaldo sin esperar (tras una venta/abono/devolución).
  void backupSoon() {
    if (enabled) unawaited(backupNow());
  }

  /// Descarga el último respaldo y reemplaza el archivo local. La app debe
  /// reiniciarse para tomar la base restaurada.
  Future<void> restoreFromCloud() async {
    if (!enabled) throw StateError('Respaldo en la nube no configurado');
    final Uint8List bytes =
        await _client.storage.from(_bucket).download(_object);
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'boutique_pos.sqlite'));
    await _db.close();
    await file.writeAsBytes(bytes, flush: true);
    // El llamador avisa que hay que reiniciar la app.
  }

  /// Foto consistente de la base vía `VACUUM INTO` (no copia archivos a medio
  /// escribir).
  Future<Uint8List> _snapshot() async {
    final dir = await getApplicationDocumentsDirectory();
    final tmp = File(p.join(dir.path, 'backup_tmp.sqlite'));
    if (await tmp.exists()) await tmp.delete();
    // SQLite acepta '/' incluso en Windows.
    final path = tmp.path.replaceAll(r'\', '/');
    await _db.customStatement("VACUUM INTO '$path'");
    final bytes = await tmp.readAsBytes();
    await tmp.delete();
    return bytes;
  }

  /// Id del dispositivo (para diagnóstico). El respaldo usa ruta fija.
  Future<String> deviceId() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals('device_id')))
        .getSingleOrNull();
    if (row != null) return row.value;
    final id = const Uuid().v4();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: 'device_id', value: id));
    return id;
  }
}
