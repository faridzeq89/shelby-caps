import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../core/pin_hash.dart';
import '../data/local/database.dart';

/// Estado de sesión del mostrador: quién está adentro y con qué rol.
class AuthController extends ChangeNotifier {
  AuthController(this._db);

  final AppDatabase _db;

  Profile? _currentUser;
  Profile? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get mustChangePin => _currentUser?.mustChangePin ?? false;
  bool get isAdmin => _currentUser?.role == UserRole.admin;

  /// Crea el administrador inicial en el primer arranque: PIN **1234** que se
  /// obliga a cambiar en el primer login.
  Future<void> ensureSeedAdmin() async {
    final existing = await _db.allProfiles();
    if (existing.isNotEmpty) return;
    final salt = PinHash.generateSalt();
    await _db.insertProfile(
      ProfilesCompanion.insert(
        name: 'Administrador',
        role: UserRole.admin,
        pinSalt: salt,
        pinHash: PinHash.hash('1234', salt),
        mustChangePin: const Value(true),
      ),
    );
  }

  /// Intenta iniciar sesión con [pin]. Devuelve `true` si algún perfil activo
  /// coincide.
  Future<bool> loginWithPin(String pin) async {
    for (final profile in await _db.activeProfiles()) {
      if (PinHash.verify(pin, profile.pinSalt, profile.pinHash)) {
        _currentUser = profile;
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// Verifica un PIN de gerente/admin para autorizar una acción (descuento
  /// grande, cancelación) sin cerrar la sesión del cajero. Devuelve el perfil
  /// autorizante o null.
  Future<Profile?> verifyPrivilegedPin(String pin) async {
    for (final profile in await _db.activeProfiles()) {
      final privileged =
          profile.role == UserRole.admin || profile.role == UserRole.manager;
      if (privileged && PinHash.verify(pin, profile.pinSalt, profile.pinHash)) {
        return profile;
      }
    }
    return null;
  }

  /// Cambia el PIN del usuario en sesión y limpia la bandera [mustChangePin].
  Future<void> changePin(String newPin) async {
    final user = _currentUser;
    if (user == null) return;
    final salt = PinHash.generateSalt();
    final updated = user.copyWith(
      pinSalt: salt,
      pinHash: PinHash.hash(newPin, salt),
      mustChangePin: false,
    );
    await _db.updateProfile(updated);
    _currentUser = updated;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}
