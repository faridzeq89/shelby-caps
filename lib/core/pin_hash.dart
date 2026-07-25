import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Hashing de PIN para el login del mostrador.
///
/// No se guarda el PIN en claro: cada perfil tiene una sal aleatoria y se
/// almacena `sha256(sal:pin)`. Suficiente para un PIN local de 4-6 dígitos en
/// una tablet dedicada; si más adelante se necesita algo más fuerte, se cambia
/// aquí sin tocar el resto.
class PinHash {
  const PinHash._();

  static String generateSalt([int length = 16]) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(length, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  static bool verify(String pin, String salt, String expectedHash) {
    return hash(pin, salt) == expectedHash;
  }
}
