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
///
/// **Restauración segura (Fase 13):** solo una tablet "reclamada" sube a la nube.
/// Una tablet nueva/recién instalada NO está reclamada, así que su base (vacía o
/// de semilla) NO sobrescribe el respaldo bueno; el usuario primero restaura de
/// la nube o pulsa "empezar a respaldar". Además se conserva un historial con
/// fecha por si un respaldo malo pisa al bueno.
class CloudBackupService extends ChangeNotifier {
  CloudBackupService(this._db, {required this.enabled}) {
    state = enabled ? SyncState.idle : SyncState.disabled;
  }

  final AppDatabase _db;
  final bool enabled;

  static const _bucket = 'backups';
  static const _object = 'boutique.sqlite';
  static const _historyPrefix = 'history';
  static const _claimedKey = 'backup_claimed';
  static const _historyStampKey = 'backup_last_history_at';
  static const _keepHistory = 10;
  static const _historyEvery = Duration(hours: 6);

  SyncState state = SyncState.disabled;
  DateTime? lastBackupAt;
  String? lastError;
  Timer? _timer;
  bool? _claimed; // caché de la bandera de "tablet reclamada"

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

  // -------------------------------------------------------------------------
  // Reclamo de la tablet (guardia contra sobrescritura)
  // -------------------------------------------------------------------------

  /// ¿Esta tablet ya reclamó el respaldo? Solo una tablet reclamada sube a la
  /// nube. Cacheado en memoria; la fuente es `app_settings`.
  Future<bool> isClaimed() async {
    if (_claimed != null) return _claimed!;
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(_claimedKey)))
        .getSingleOrNull();
    _claimed = row?.value == 'true';
    return _claimed!;
  }

  /// Valor cacheado para la UI (ya cargado al arrancar por [autoClaimIfHasData]).
  bool get isClaimedCached => _claimed ?? false;

  /// Marca esta tablet como dueña del respaldo: a partir de aquí sí sube.
  Future<void> markClaimed() async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: _claimedKey, value: 'true'));
    _claimed = true;
    notifyListeners();
  }

  /// Un install existente (la base ya tiene ventas) reclama automáticamente, para
  /// no interrumpir el respaldo tras una actualización. Una tablet NUEVA (sin
  /// ventas) NO se reclama sola: el usuario decide (restaurar o "empezar a
  /// respaldar"), y mientras tanto la nube queda protegida.
  Future<void> autoClaimIfHasData() async {
    if (await isClaimed()) return;
    final row =
        await _db.customSelect('SELECT COUNT(*) AS n FROM sales').getSingle();
    if (row.read<int>('n') > 0) await markClaimed();
  }

  // -------------------------------------------------------------------------
  // Respaldo
  // -------------------------------------------------------------------------

  /// Sube una foto consistente de la base. No lanza: reporta el estado. No sube
  /// si la tablet no está reclamada (protege el respaldo bueno).
  Future<void> backupNow() async {
    if (!enabled || state == SyncState.syncing) return;
    if (!await isClaimed()) return; // tablet nueva: no pisar la nube
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
      await _maybeSnapshotHistory(bytes); // extra, nunca rompe el principal
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
  /// reiniciarse para tomar la base restaurada. La base restaurada trae su
  /// propia bandera de reclamada (venía de una tablet reclamada), así que tras
  /// reiniciar esta tablet sí respalda.
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

  /// Guarda una copia con fecha en `history/`, espaciada (cada [_historyEvery]),
  /// y poda a las últimas [_keepHistory]. Es un extra: cualquier fallo se ignora
  /// para no afectar el respaldo principal.
  Future<void> _maybeSnapshotHistory(Uint8List bytes) async {
    try {
      final now = DateTime.now();
      final last = await _readHistoryStamp();
      if (last != null && now.difference(last) < _historyEvery) return;

      final stamp = now.toUtc().toIso8601String().replaceAll(':', '-');
      await _client.storage.from(_bucket).uploadBinary(
            '$_historyPrefix/boutique-$stamp.sqlite',
            bytes,
            fileOptions:
                const FileOptions(contentType: 'application/octet-stream'),
          );
      await _writeHistoryStamp(now);
      await _pruneHistory();
    } catch (_) {
      // Historial best-effort: nunca rompe el respaldo principal.
    }
  }

  Future<void> _pruneHistory() async {
    final items = await _client.storage.from(_bucket).list(path: _historyPrefix);
    if (items.length <= _keepHistory) return;
    final names = items.map((f) => f.name).toList()..sort();
    final remove = names
        .take(names.length - _keepHistory)
        .map((n) => '$_historyPrefix/$n')
        .toList();
    if (remove.isNotEmpty) {
      await _client.storage.from(_bucket).remove(remove);
    }
  }

  Future<DateTime?> _readHistoryStamp() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(_historyStampKey)))
        .getSingleOrNull();
    return row == null ? null : DateTime.tryParse(row.value);
  }

  Future<void> _writeHistoryStamp(DateTime when) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
            key: _historyStampKey, value: when.toIso8601String()));
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
