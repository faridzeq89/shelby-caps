import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui_kit.dart';
import '../../services/auth_controller.dart';
import '../admin/access_screen.dart';
import '../admin/banners_screen.dart';
import '../admin/business_card_screen.dart';
import '../admin/cloud_backup_screen.dart';
import '../admin/demo_catalog_screen.dart';
import '../admin/loyalty_config_screen.dart';
import '../admin/palette_screen.dart';
import '../admin/printers_screen.dart';
import '../admin/quick_menu_screen.dart';
import '../admin/tax_settings_screen.dart';
import '../admin/reconciliation_screen.dart';
import '../admin/users_screen.dart';
import '../catalog/catalog_home_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../sales/gift_cards_screen.dart';
import '../sales/layaways_screen.dart';
import '../sales/quotes_screen.dart';
import '../sales/returns_screen.dart';
import '../suppliers/suppliers_screen.dart';

/// Menú lateral (hamburguesa) con TODAS las funciones agrupadas. Las 4 más usadas
/// viven en el bottom-nav (Inicio · Vender · Inventario · Balance) y también se
/// pueden abrir desde aquí vía [onGoTab]; el resto se abre como pantalla.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onGoTab});

  /// Cambia de pestaña principal: 0 Inicio · 1 Vender · 2 Inventario · 3 Balance.
  final void Function(int index) onGoTab;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final isAdmin = auth.isAdmin;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void goTab(int i) {
      Navigator.of(context).pop();
      onGoTab(i);
    }

    void push(Widget screen) {
      Navigator.of(context).pop();
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      backgroundColor: theme.cardColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Cabecera carbón con la marca.
          Container(
            color: AppColors.bar,
            padding: EdgeInsets.fromLTRB(
                18, MediaQuery.of(context).padding.top + 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: AppColors.brand, shape: BoxShape.circle),
                      child: Icon(Icons.local_mall_outlined,
                          color: AppColors.onAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('SHELBY CAPS',
                        style: TextStyle(
                            color: AppColors.onBar,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${auth.currentUser?.name ?? ''} · ${_roleLabel(isAdmin)}',
                  style: TextStyle(
                      color: AppColors.onBarMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          _group('Vender'),
          _item(context, Icons.point_of_sale, 'Punto de venta',
              onTap: () => goTab(1)),
          _item(context, Icons.request_quote_outlined, 'Cotizaciones',
              onTap: () => push(const QuotesScreen())),
          _item(context, Icons.bookmark_border, 'Apartados',
              onTap: () => push(const LayawaysScreen())),
          _item(context, Icons.assignment_return_outlined, 'Devoluciones',
              onTap: () => push(const ReturnsScreen())),
          _item(context, Icons.card_giftcard, 'Tarjetas de regalo',
              onTap: () => push(const GiftCardsScreen())),

          _group('Catálogo y stock'),
          _item(context, Icons.inventory_2_outlined, 'Inventario',
              onTap: () => goTab(2)),
          if (isAdmin)
            _item(context, Icons.storefront_outlined, 'Catálogo (productos)',
                onTap: () => push(const CatalogHomeScreen())),
          if (isAdmin)
            _item(context, Icons.local_shipping_outlined, 'Proveedores',
                onTap: () => push(const SuppliersScreen())),
          _group('Clientes y dinero'),
          _item(context, Icons.people_alt_outlined, 'Clientes',
              onTap: () => push(const CustomersScreen())),
          if (isAdmin)
            _item(context, Icons.stars_outlined, 'Lealtad (puntos)',
                onTap: () => push(const LoyaltyConfigScreen())),
          _item(context, Icons.bar_chart_outlined, 'Balance y reportes',
              onTap: () => goTab(3)),
          if (isAdmin)
            _item(context, Icons.receipt_long_outlined, 'Gastos',
                onTap: () => push(const ExpensesScreen())),

          if (isAdmin) ...[
            _group('Ajustes'),
            _item(context, Icons.print_outlined, 'Impresoras y tickets',
                onTap: () => push(const PrintersScreen())),
            _item(context, Icons.groups_outlined, 'Usuarios',
                onTap: () => push(const UsersScreen())),
            _item(context, Icons.lock_outline, 'Acceso',
                onTap: () => push(const AccessScreen())),
            _item(context, Icons.cloud_outlined, 'Respaldo (nube)',
                onTap: () => push(const CloudBackupScreen())),
            _item(context, Icons.rule, 'Reconciliación',
                onTap: () => push(const ReconciliationScreen())),
            _item(context, Icons.palette_outlined, 'Colores',
                onTap: () => push(const PaletteScreen())),
            _item(context, Icons.dashboard_customize_outlined, 'Menú rápido',
                onTap: () => push(const QuickMenuScreen())),
            _item(context, Icons.percent, 'IVA',
                onTap: () => push(const TaxSettingsScreen())),
            _item(context, Icons.campaign_outlined, 'Anuncios de la tienda',
                onTap: () => push(const BannersScreen())),
            _item(context, Icons.badge_outlined, 'Tarjeta digital',
                onTap: () => push(const BusinessCardScreen())),
            _item(context, Icons.science_outlined, 'Catálogo de prueba',
                onTap: () => push(const DemoCatalogScreen())),
          ],

          const Divider(height: 24),
          ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text('Cerrar sesión',
                style: TextStyle(
                    color: scheme.error, fontWeight: FontWeight.w700)),
            onTap: () {
              Navigator.of(context).pop();
              _confirmLogout(context, auth);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  String _roleLabel(bool isAdmin) => isAdmin ? 'Propietario' : 'Cajero';

  Widget _group(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2)),
      );

  Widget _item(BuildContext context, IconData icon, String label,
      {required VoidCallback onTap, String? trailing}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.accent),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      trailing: trailing == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(trailing.toUpperCase(),
                  style: TextStyle(
                      color: AppColors.onAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900)),
            ),
      onTap: onTap,
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthController auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Salir de tu sesión?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true) auth.logout();
  }
}
