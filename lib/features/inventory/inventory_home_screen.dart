import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/permissions.dart';
import '../../data/local/database.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../services/auth_controller.dart';
import 'adjust_stock_screen.dart';
import 'low_stock_screen.dart';
import 'receive_stock_screen.dart';
import 'stock_count_screen.dart';

/// Centro de operaciones de inventario: recepción, ajustes, conteo físico y
/// alertas de stock bajo. Las operaciones que mueven stock exigen gerente/admin;
/// el cajero solo consulta el stock bajo.
class InventoryHomeScreen extends StatefulWidget {
  const InventoryHomeScreen({super.key});

  @override
  State<InventoryHomeScreen> createState() => _InventoryHomeScreenState();
}

class _InventoryHomeScreenState extends State<InventoryHomeScreen> {
  late final InventoryRepository _inventory =
      InventoryRepository(context.read<AppDatabase>());
  int _lowStock = 0;

  bool get _canManage => Permissions.canManageInventory(
      context.read<AuthController>().currentUser!.role);

  @override
  void initState() {
    super.initState();
    _refreshLowStock();
  }

  Future<void> _refreshLowStock() async {
    final n = await _inventory.lowStockCount();
    if (mounted) setState(() => _lowStock = n);
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    _refreshLowStock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventario')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            icon: Icons.local_shipping_outlined,
            title: 'Recepción de mercancía',
            subtitle: 'Registrar entradas por escaneo o búsqueda',
            enabled: _canManage,
            onTap: () => _open(const ReceiveStockScreen()),
          ),
          _card(
            icon: Icons.tune,
            title: 'Ajuste de inventario',
            subtitle: 'Merma, dañado, robo o corrección (con motivo)',
            enabled: _canManage,
            onTap: () => _open(const AdjustStockScreen()),
          ),
          _card(
            icon: Icons.fact_check_outlined,
            title: 'Conteo físico',
            subtitle: 'Contar, ver diferencias y ajustar en lote',
            enabled: _canManage,
            onTap: () => _open(const StockCountScreen()),
          ),
          _card(
            icon: Icons.notifications_active_outlined,
            title: 'Stock bajo',
            subtitle: _lowStock == 0
                ? 'Nada bajo mínimo'
                : '$_lowStock variantes bajo mínimo',
            badge: _lowStock,
            enabled: true,
            onTap: () => _open(const LowStockScreen()),
          ),
          if (!_canManage)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                'Recepción, ajustes y conteo requieren rol de gerente o administrador.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    Widget leading = Icon(icon);
    if (badge > 0) {
      leading = Badge(label: Text('$badge'), child: leading);
    }
    return Card(
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : const Icon(Icons.lock_outline),
        enabled: enabled,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
