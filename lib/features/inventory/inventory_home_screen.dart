import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dashboard_tile.dart';
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
  const InventoryHomeScreen({super.key, this.onMenu});

  /// Si se provee, muestra la hamburguesa que abre el menú del shell.
  final VoidCallback? onMenu;

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
      appBar: AppBar(
        leading: widget.onMenu == null
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: widget.onMenu,
                tooltip: 'Menú'),
        title: const Text('Inventario'),
      ),
      body: Column(
        children: [
          Expanded(
            child: DashboardGrid(
              children: [
                DashboardTile(
                  icon: Icons.local_shipping_outlined,
                  color: Colors.teal,
                  title: 'Recepción',
                  subtitle: 'Registrar entradas por escaneo o búsqueda',
                  enabled: _canManage,
                  onTap: () => _open(const ReceiveStockScreen()),
                ),
                DashboardTile(
                  icon: Icons.tune,
                  color: Colors.orange.shade800,
                  title: 'Ajuste',
                  subtitle: 'Merma, dañado, robo o corrección (con motivo)',
                  enabled: _canManage,
                  onTap: () => _open(const AdjustStockScreen()),
                ),
                DashboardTile(
                  icon: Icons.fact_check_outlined,
                  color: Colors.indigo,
                  title: 'Conteo físico',
                  subtitle: 'Contar, ver diferencias y ajustar en lote',
                  enabled: _canManage,
                  onTap: () => _open(const StockCountScreen()),
                ),
                DashboardTile(
                  icon: Icons.notifications_active_outlined,
                  color: Colors.red.shade600,
                  title: 'Stock bajo',
                  subtitle: _lowStock == 0
                      ? 'Nada bajo mínimo'
                      : '$_lowStock variantes bajo mínimo',
                  badge: _lowStock,
                  onTap: () => _open(const LowStockScreen()),
                ),
              ],
            ),
          ),
          if (!_canManage)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Recepción, ajustes y conteo requieren rol de gerente o administrador.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
