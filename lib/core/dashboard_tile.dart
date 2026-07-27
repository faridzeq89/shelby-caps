import 'package:flutter/material.dart';

/// Mosaico reutilizable para pantallas tipo panel: icono en círculo de color,
/// título y subtítulo. Soporta badge (contador) y estado deshabilitado.
class DashboardTile extends StatelessWidget {
  const DashboardTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
    this.badge = 0,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  final int badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = enabled
        ? (color ?? theme.colorScheme.primary)
        : theme.disabledColor;

    Widget iconBox = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(enabled ? icon : Icons.lock_outline, color: c, size: 26),
    );
    if (badge > 0) {
      iconBox = Badge(label: Text('$badge'), child: iconBox);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconBox,
                const SizedBox(height: 8),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                // Flexible: si el subtítulo no cabe, se recorta en vez de desbordar.
                Flexible(
                  child: Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rejilla responsiva de [DashboardTile] (o cualquier widget). Se adapta al
/// ancho: más columnas en tablet. Úsala como `body` o dentro de un scroll.
class DashboardGrid extends StatelessWidget {
  const DashboardGrid({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(16),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return GridView.extent(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      maxCrossAxisExtent: 230,
      mainAxisExtent: 158,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      children: children,
    );
  }
}
