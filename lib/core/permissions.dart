import '../data/local/schema.dart';

/// Se lanza cuando un rol intenta una acción que no le corresponde.
class PermissionException implements Exception {
  PermissionException(this.message);
  final String message;

  @override
  String toString() => 'PermissionException: $message';
}

/// Capacidades por rol. La frontera de seguridad del POS es la app (no hay
/// servidor en operación normal); la RLS de Supabase solo cuida el respaldo.
///
/// El cajero vende pero no edita precios, no ve costos ni administra catálogo.
class Permissions {
  const Permissions._();

  static bool canEditPrices(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  static bool canSeeCosts(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  static bool canManageCatalog(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  static bool canManageUsers(UserRole role) => role == UserRole.admin;

  /// Registrar y borrar gastos del negocio.
  static bool canManageExpenses(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  static bool canAuthorizeDiscount(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  static bool canCancelSale(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;

  /// Recibir mercancía, ajustar stock, correr conteos y fijar mínimos. El
  /// cajero puede consultar el inventario, pero no moverlo.
  static bool canManageInventory(UserRole role) =>
      role == UserRole.admin || role == UserRole.manager;
}
