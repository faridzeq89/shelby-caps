import 'package:flutter/material.dart';

/// Sistema visual "premium" de Montana Boutique (Material 3):
/// base blanca, superficies limpias con **borde gris suave + sombra tenue**,
/// **botones morados** de alto contraste, inputs blancos, y diálogos/menús
/// redondeados con sombra. Como las pantallas usan componentes Material
/// estándar, este tema las estiliza TODAS de forma consistente.
ThemeData buildAppTheme() {
  const brand = Color(0xFF7A1F5C); // ciruela/morado de la marca (y del icono)
  const bg = Color(0xFFF5F4F7); // base casi blanca
  const border = Color(0xFFE4E2E8); // borde gris suave
  const ink = Color(0xFF1B1B1F); // texto principal
  final shadow = Colors.black.withValues(alpha: 0.06);

  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: Brightness.light,
  ).copyWith(primary: brand, surface: Colors.white);

  OutlineInputBorder ob(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  final menuShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
    side: const BorderSide(color: border),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,

    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),

    cardTheme: CardThemeData(
      elevation: 2,
      color: Colors.white,
      shadowColor: shadow,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: border),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: brand,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 3,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: shadow,
      indicatorColor: brand.withValues(alpha: 0.12),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        elevation: 1,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: brand,
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: brand.withValues(alpha: 0.12),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: ob(border),
      enabledBorder: ob(border),
      focusedBorder: ob(brand, 2),
      floatingLabelStyle: const TextStyle(color: brand),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: shadow,
      shape: menuShape,
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shadowColor: WidgetStatePropertyAll(shadow),
        shape: WidgetStatePropertyAll(menuShape),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: border,
      space: 1,
      thickness: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
          color: ink, fontSize: 20, fontWeight: FontWeight.w700),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
