import '../data/local/database.dart';

/// Etiquetas en español para los roles del sistema.
extension UserRoleLabel on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Administrador',
        UserRole.manager => 'Gerente',
        UserRole.cashier => 'Cajero',
      };
}
