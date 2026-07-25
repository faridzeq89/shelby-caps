import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Roles del sistema. El orden importa poco, pero no reordenar sin migración:
/// `textEnum` guarda el nombre (`admin`/`manager`/`cashier`), no el índice.
enum UserRole { admin, manager, cashier }

/// Usuarios del punto de venta. Login por PIN (ver [pinHash]/[pinSalt]).
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  TextColumn get role => textEnum<UserRole>()();
  TextColumn get pinSalt => text()();
  TextColumn get pinHash => text()();
  BoolColumn get mustChangePin =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Profiles])
class AppDatabase extends _$AppDatabase {
  /// Sin argumentos abre la base local en el dispositivo. Los tests pueden
  /// inyectar un ejecutor en memoria: `AppDatabase(NativeDatabase.memory())`.
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  Future<List<Profile>> allProfiles() => select(profiles).get();

  Future<List<Profile>> activeProfiles() =>
      (select(profiles)..where((t) => t.active.equals(true))).get();

  Future<int> insertProfile(ProfilesCompanion entry) =>
      into(profiles).insert(entry);

  Future<bool> updateProfile(Profile entry) => update(profiles).replace(entry);

  static LazyDatabase _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'boutique_pos.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
