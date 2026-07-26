import 'package:drift/drift.dart';

import '../../core/permissions.dart';
import '../../core/pin_hash.dart';
import '../local/database.dart';

/// Gestión de usuarios del mostrador (solo admin). No borra perfiles: los
/// desactiva, para conservar la atribución histórica de ventas y auditoría.
class UserRepository {
  UserRepository(this._db);
  final AppDatabase _db;

  void _requireAdmin(Profile actor) {
    if (!Permissions.canManageUsers(actor.role)) {
      throw PermissionException(
          'Solo un administrador puede gestionar usuarios');
    }
  }

  void _validatePin(String pin) {
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw ArgumentError('El PIN debe ser de 4 a 6 dígitos');
    }
  }

  Future<List<Profile>> listUsers() =>
      (_db.select(_db.profiles)..orderBy([(t) => OrderingTerm(expression: t.name)]))
          .get();

  /// Rechaza si algún perfil ACTIVO ya usa ese PIN (evita logins ambiguos: el
  /// login es solo por PIN, así que dos iguales colisionan).
  Future<void> _ensurePinFree(String pin, {int? exceptUserId}) async {
    for (final p in await _db.activeProfiles()) {
      if (p.id == exceptUserId) continue;
      if (PinHash.verify(pin, p.pinSalt, p.pinHash)) {
        throw ArgumentError('Ese PIN ya está en uso por otro usuario');
      }
    }
  }

  /// Crea un usuario con [role] y PIN inicial. Se obliga a cambiarlo en el
  /// primer login (mustChangePin).
  Future<int> createUser(
    Profile actor, {
    required String name,
    required UserRole role,
    required String pin,
  }) async {
    _requireAdmin(actor);
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('El nombre es obligatorio');
    _validatePin(pin);
    await _ensurePinFree(pin);

    final salt = PinHash.generateSalt();
    final id = await _db.insertProfile(ProfilesCompanion.insert(
      name: cleanName,
      role: role,
      pinSalt: salt,
      pinHash: PinHash.hash(pin, salt),
      mustChangePin: const Value(true),
    ));
    await _audit(actor, 'create_user', id, 'name=$cleanName; role=${role.name}');
    return id;
  }

  /// Activa o desactiva un usuario. No permite desactivarse a sí mismo ni dejar
  /// al sistema sin ningún admin activo.
  Future<void> setActive(Profile actor, int userId, bool active) async {
    _requireAdmin(actor);
    final user = await _userById(userId);
    if (!active) {
      if (userId == actor.id) {
        throw StateError('No puedes desactivar tu propia cuenta');
      }
      if (user.role == UserRole.admin && await _activeAdminCount() <= 1) {
        throw StateError('Debe quedar al menos un administrador activo');
      }
    }
    await (_db.update(_db.profiles)..where((t) => t.id.equals(userId)))
        .write(ProfilesCompanion(active: Value(active)));
    await _audit(actor, active ? 'enable_user' : 'disable_user', userId,
        'name=${user.name}');
  }

  /// Reinicia el PIN de un usuario (lo obliga a cambiarlo en el próximo login).
  Future<void> resetPin(Profile actor, int userId, String newPin) async {
    _requireAdmin(actor);
    _validatePin(newPin);
    await _ensurePinFree(newPin, exceptUserId: userId);
    final salt = PinHash.generateSalt();
    await (_db.update(_db.profiles)..where((t) => t.id.equals(userId))).write(
      ProfilesCompanion(
        pinSalt: Value(salt),
        pinHash: Value(PinHash.hash(newPin, salt)),
        mustChangePin: const Value(true),
      ),
    );
    await _audit(actor, 'reset_pin', userId, '');
  }

  Future<int> _activeAdminCount() async {
    final admins = await (_db.select(_db.profiles)
          ..where((t) => t.active.equals(true) & t.role.equalsValue(UserRole.admin)))
        .get();
    return admins.length;
  }

  Future<Profile> _userById(int id) =>
      (_db.select(_db.profiles)..where((t) => t.id.equals(id))).getSingle();

  Future<void> _audit(Profile actor, String action, int userId, String detail) =>
      _db.into(_db.auditLog).insert(AuditLogCompanion.insert(
            userId: Value(actor.id),
            action: action,
            entityType: 'profile',
            entityId: Value(userId.toString()),
            detail: Value(detail),
          ));
}
