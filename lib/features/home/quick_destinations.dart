import 'package:flutter/material.dart';

import '../customers/customers_screen.dart';
import '../expenses/expenses_screen.dart';
import '../sales/gift_cards_screen.dart';
import '../sales/layaways_screen.dart';
import '../sales/quotes_screen.dart';
import '../sales/returns_screen.dart';
import '../suppliers/suppliers_screen.dart';

/// Una entrada posible del menú rápido de abajo.
///
/// Hay dos clases y la diferencia importa:
///
/// - **Pestañas** ([tabIndex] no nulo): Inicio, Vender, Inventario y Balance
///   viven siempre en el `IndexedStack` y conservan su estado. Por eso el
///   carrito no se pierde aunque el dueño quite "Vender" de la barra: la
///   pantalla sigue ahí, solo deja de tener atajo.
/// - **Atajos** ([builder] no nulo): abren una pantalla encima. No se quedan
///   marcados como seleccionados porque no son un lugar donde uno "está".
class QuickDestination {
  const QuickDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.tabIndex,
    this.builder,
    this.adminOnly = false,
  }) : assert(tabIndex != null || builder != null,
            'Un destino es pestaña o abre una pantalla');

  /// Clave estable con la que se guarda la configuración. **No renombrar**: es
  /// lo que queda escrito en la base del dueño.
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// Pestaña del shell (0 Inicio · 1 Vender · 2 Inventario · 3 Balance).
  final int? tabIndex;

  /// Pantalla que se abre encima, para los atajos.
  final Widget Function()? builder;

  final bool adminOnly;

  bool get isTab => tabIndex != null;
}

/// Todo lo que se puede poner en la barra de abajo. El orden de esta lista es
/// el que se ofrece al configurar.
const quickDestinations = <QuickDestination>[
  QuickDestination(
    id: 'inicio',
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    tabIndex: 0,
  ),
  QuickDestination(
    id: 'vender',
    label: 'Vender',
    icon: Icons.point_of_sale_outlined,
    selectedIcon: Icons.point_of_sale,
    tabIndex: 1,
  ),
  QuickDestination(
    id: 'inventario',
    label: 'Inventario',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    tabIndex: 2,
  ),
  QuickDestination(
    id: 'balance',
    label: 'Balance',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    tabIndex: 3,
  ),
  QuickDestination(
    id: 'cotizaciones',
    label: 'Cotizar',
    icon: Icons.request_quote_outlined,
    selectedIcon: Icons.request_quote,
    builder: QuotesScreen.new,
  ),
  QuickDestination(
    id: 'apartados',
    label: 'Apartados',
    icon: Icons.bookmark_border,
    selectedIcon: Icons.bookmark,
    builder: LayawaysScreen.new,
  ),
  QuickDestination(
    id: 'devoluciones',
    label: 'Devoluciones',
    icon: Icons.assignment_return_outlined,
    selectedIcon: Icons.assignment_return,
    builder: ReturnsScreen.new,
  ),
  QuickDestination(
    id: 'giftcards',
    label: 'Tarjetas',
    icon: Icons.card_giftcard,
    selectedIcon: Icons.card_giftcard,
    builder: GiftCardsScreen.new,
  ),
  QuickDestination(
    id: 'clientes',
    label: 'Clientes',
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt,
    builder: CustomersScreen.new,
  ),
  QuickDestination(
    id: 'gastos',
    label: 'Gastos',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    builder: ExpensesScreen.new,
    adminOnly: true,
  ),
  QuickDestination(
    id: 'proveedores',
    label: 'Proveedores',
    icon: Icons.local_shipping_outlined,
    selectedIcon: Icons.local_shipping,
    builder: SuppliersScreen.new,
    adminOnly: true,
  ),
];

QuickDestination? destinationById(String id) {
  for (final d in quickDestinations) {
    if (d.id == id) return d;
  }
  return null;
}
