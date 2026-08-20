import 'package:flutter/material.dart';

import 'ui_kit.dart';

/// Sistema visual de SHELBY CAPS (Material 3): **vino sobre gris casi negro**.
/// Fondo oscuro, texto blanco y gris claro según jerarquía, y el vino solo
/// donde hay que llevar la vista: acciones, selección y acentos.
///
/// En oscuro las sombras no se ven, así que las tarjetas se separan del fondo
/// por **luz y borde**: la superficie es un escalón más clara que el fondo.
///
/// La paleta vive en [AppColors] (`ui_kit.dart`), que es la única fuente de
/// verdad: cambiar el vino ahí re-tinta la app entera, tema y primitivos.
ThemeData buildAppTheme() {
  final brand = AppColors.brand;
  final accent = AppColors.accent;
  final bar = AppColors.bar;
  final onBar = AppColors.onBar;
  final onAccent = AppColors.onAccent;
  final bg = AppColors.bg;
  final surface = AppColors.surface;
  final border = AppColors.border;
  final ink = AppColors.ink;
  final inkMuted = AppColors.inkMuted;
  // ¿La paleta que eligió el dueño es oscura? Se deduce midiendo el fondo, no
  // con una bandera aparte que se pueda desincronizar de los colores.
  final esOscuro = bg.computeLuminance() < 0.5;

  // En oscuro la sombra apenas se percibe; en claro una sombra negra al 50 %
  // ensucia todo, así que se suaviza.
  final shadow = Colors.black.withValues(alpha: esOscuro ? 0.5 : 0.16);

  // El brillo TIENE que seguir a la paleta. Estaba fijo en `dark`, y con fondo
  // claro Flutter seguía pintando de blanco todo icono sin color propio: el ⋮
  // de los menús y el asa de arrastrar desaparecían sobre las tarjetas (lo
  // reportó el cliente el 20 ago 2026, con el tema en claro).
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: esOscuro ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: brand,
    onPrimary: onAccent,
    secondary: accent,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: inkMuted,
    error: AppColors.danger,
    onError: Colors.black,
    outline: border,
  );

  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  final menuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: BorderSide(color: border),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito', // tipografía redondeada de la marca
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    // Muchas pantallas usan `theme.hintColor` para lo secundario (iconos
    // apagados, ayudas). Se fija al gris claro de la paleta para que la
    // jerarquía sea la misma en toda la app.
    hintColor: inkMuted,

    // Iconos del cuerpo (los que no traen color propio): el tinte de la paleta,
    // no el blanco/negro que Flutter deduce del brillo. Así un menú ⋮ se lee
    // igual en claro y en oscuro.
    iconTheme: IconThemeData(color: ink),

    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: bar,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onBar,
      iconTheme: IconThemeData(color: onBar),
      titleTextStyle: TextStyle(
        color: onBar,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 2,
      color: surface,
      shadowColor: shadow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 3,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadow,
      indicatorColor: brand.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    // CTA principal: vino con texto blanco.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: onAccent,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    // Acción secundaria: sobre el fondo oscuro un botón "más oscuro" se pierde,
    // así que sube un escalón de luz en vez de bajarlo.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF26262E),
        foregroundColor: ink,
        elevation: 1,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(0, 50),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand,
      foregroundColor: onAccent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: brand.withValues(alpha: 0.16),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(border),
      enabledBorder: ob(border),
      focusedBorder: ob(brand, 2),
      floatingLabelStyle: TextStyle(color: accent),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: shadow,
      shape: menuShape,
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shadowColor: WidgetStatePropertyAll(shadow),
        shape: WidgetStatePropertyAll(menuShape),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: border,
      space: 1,
      thickness: 1,
    ),

    // El aviso flotante se deja claro sobre oscuro a propósito: es temporal y
    // tiene que saltar a la vista sin confundirse con una tarjeta.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2E2E38),
      contentTextStyle: TextStyle(color: ink, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
          color: ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
