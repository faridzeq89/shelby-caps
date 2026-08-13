/// Primitivos visuales de "Sastrería Moderna" (SHELBY CAPS).
///
/// El tema (`buildAppTheme`) estiliza los componentes Material estándar; esto
/// cubre lo que Material no da: la tarjeta con borde greige, las píldoras de
/// estado, los mosaicos de acceso rápido y los encabezados de sección.
///
/// **Regla:** ninguna pantalla define colores ni radios propios. Si algo no se
/// puede armar con estos primitivos, se agrega aquí — no se copia en la pantalla.
library;

import 'package:flutter/material.dart';

import 'palette.dart';

/// Paleta de la marca. Única fuente de verdad: el tema la consume, y las
/// pantallas que necesiten un color semántico (éxito, atenuado) lo toman de aquí
/// en vez de escribir el hexadecimal.
abstract final class AppColors {
  /// Repinta la paleta con la que eligió el dueño. La llama el arranque y la
  /// pantalla de Colores; después basta con reconstruir la app.
  ///
  /// Son variables globales a propósito: la app tiene **un** tema, y la
  /// alternativa (pasar la paleta por `context` en 85 lugares) sería más ruido
  /// que beneficio para lo mismo.
  static void apply(Palette p) {
    brand = p.brand;
    accent = p.accent;
    onAccent = p.onAccent;
    bar = p.bar;
    onBar = p.onBar;
    onBarMuted = p.onBarMuted;
    bg = p.bg;
    surface = p.surface;
    border = p.border;
    ink = p.ink;
    inkMuted = p.inkMuted;
    success = p.success;
    danger = p.danger;
  }

  /// Vino tirando a rojo: relleno de las acciones principales. Lleva poco azul
  /// a propósito — en cuanto el azul sube, el vino se lee rosa.
  static Color brand = Color(0xFFA81C22);

  /// Rojo claro para **texto e iconos** sobre fondo oscuro. El [brand] relleno
  /// no alcanza contraste como texto; este sí, sin irse al rosa.
  static Color accent = Color(0xFFED5147);

  /// Texto sobre el vino relleno.
  static Color onAccent = Color(0xFFFFFFFF);

  /// Barras de app: un escalón más oscuro que el fondo, para anclar la pantalla.
  static Color bar = Color(0xFF0E0E11);

  /// Texto sobre las barras.
  static Color onBar = Color(0xFFF2F2F5);

  /// Atenuado sobre las barras (subtítulos del header).
  static Color onBarMuted = Color(0xFF9B9BA6);

  /// Fondo base: gris muy oscuro, casi negro.
  static Color bg = Color(0xFF121215);

  /// Tarjetas e inputs: un escalón MÁS CLARO que el fondo. En oscuro las
  /// sombras no se ven, así que la separación se hace con luz y borde.
  static Color surface = Color(0xFF1B1B20);

  /// Borde tenue entre superficies.
  static Color border = Color(0xFF2B2B33);

  /// Texto principal (blanco cálido, no blanco puro: cansa menos).
  static Color ink = Color(0xFFF4F4F7);

  /// Texto secundario. La jerarquía se hace con esto, no con tamaños raros.
  static Color inkMuted = Color(0xFFA9A9B4);

  /// Verde: saldos a favor, stock sano, cobros completados. Aclarado respecto
  /// al tema claro porque un verde oscuro desaparece sobre negro.
  static Color success = Color(0xFF4FBF87);

  /// Alarma: acciones destructivas y faltantes. Va corrido hacia el **naranja**
  /// a propósito: con una marca roja, un rojo de error idéntico al de la marca
  /// deja de avisar nada. Aquí el tono separa "borrar" de "cobrar".
  ///
  /// Se usa donde no hay un `ColorScheme` a la mano; si lo hay, prefiere
  /// `theme.colorScheme.error`.
  static Color danger = Color(0xFFFF8A3D);
}

/// Radios del sistema. `surface` para tarjetas y filas, `control` para campos y
/// botones, `pill` para píldoras.
abstract final class AppRadii {
  static const double surface = 16;
  static const double control = 14;
  static const double small = 12;
  static const double pill = 999;
}

/// Formatea centavos como precio. `decimals: false` para cifras de panel
/// (`$1,240`), `true` para importes exactos de ticket (`$1,240.50`).
String money(int cents, {bool decimals = true}) {
  final v = cents / 100;
  final s = decimals ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
  final parts = s.split('.');
  final buf = StringBuffer();
  final digits = parts[0].replaceFirst('-', '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final sign = cents < 0 ? '-' : '';
  final dec = parts.length > 1 ? '.${parts[1]}' : '';
  return '$sign\$$buf$dec';
}

/// Superficie de papel con borde greige: la unidad de composición de la app.
/// Si recibe [onTap] se vuelve tocable con ondas contenidas al radio.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.radius = AppRadii.surface,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// Encabezado de sección: título a la izquierda, acción opcional a la derecha.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Píldora de estado (stock, saldo, forma de pago). El color define el tono:
/// el texto va en ese color y el fondo es el mismo al 12 %.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta chica + cifra grande. Es el bloque de dato de toda la app: el
/// resumen del día, los totales del carrito y los KPIs de reportes.
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.size = 20,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color? color;
  final double size;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// [StatBlock] dentro de su propia superficie, para rejillas de indicadores.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.size = 20,
  });

  final String label;
  final String value;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: StatBlock(label: label, value: value, color: color, size: size),
    );
  }
}

/// Mosaico cuadrado de acceso rápido: icono en latón y etiqueta corta.
class QuickTile extends StatelessWidget {
  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

/// Rejilla de [QuickTile] que no hace scroll propio (va dentro de una lista).
class QuickTileRow extends StatelessWidget {
  const QuickTileRow({super.key, required this.tiles, this.columns = 4});

  final List<QuickTile> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.85,
      children: tiles,
    );
  }
}

/// Campo de búsqueda estándar (lupa + placeholder).
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.autofocus = false,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }
}

/// Fila horizontal de filtros. [labels] va indexado igual que [selected].
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Align(
          child: ChoiceChip(
            label: Text(labels[i]),
            selected: selectedIndex == i,
            onSelected: (_) => onSelected(i),
          ),
        ),
      ),
    );
  }
}

/// Estado vacío: icono atenuado, qué pasa y qué hacer. Reemplaza los
/// `Center(child: Text('Sin resultados'))` sueltos.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.dividerColor),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Título de dos líneas para el `AppBar`: marca arriba, contexto abajo.
/// Es el header que estrenó Inicio; lo usan todas las pantallas del shell.
class AppBarTitle extends StatelessWidget {
  const AppBarTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.onBarMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
      ],
    );
  }
}
