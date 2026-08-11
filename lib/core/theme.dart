import 'package:flutter/material.dart';

/// Sistema visual "Sastrería Moderna" de SHELBY CAPS (Material 3):
/// **latón sobre carbón** en fondo "lana" — barras de app en carbón, acciones y
/// acentos en latón, tarjetas de papel con borde suave y sombra tenue. Como las
/// pantallas usan componentes Material estándar, este tema las estiliza TODAS
/// de forma consistente. El color de marca vive aquí: cambiarlo re-tinta la app.
ThemeData buildAppTheme() {
  const brand = Color(0xFF9C7A2C); // latón (acento / primary)
  const brassDeep = Color(0xFF846826); // latón oscuro para texto/enlaces (contraste)
  const charcoal = Color(0xFF20242A); // carbón (barras de app)
  const charcoalInk = Color(0xFFEDE7D8); // texto sobre carbón
  const onBrass = Color(0xFF17140C); // texto sobre latón
  const bg = Color(0xFFECE8DE); // lana clara (fondo)
  const surface = Color(0xFFFBFAF6); // papel (tarjetas / inputs)
  const border = Color(0xFFD4CEC1); // borde greige suave
  const ink = Color(0xFF1A1917); // texto principal
  final shadow = Colors.black.withValues(alpha: 0.06);

  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    brightness: Brightness.light,
  ).copyWith(primary: brand, onPrimary: onBrass, surface: surface);

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
      backgroundColor: charcoal,
      surfaceTintColor: Colors.transparent,
      foregroundColor: charcoalInk,
      iconTheme: IconThemeData(color: charcoalInk),
      titleTextStyle: TextStyle(
        color: charcoalInk,
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
        side: const BorderSide(color: border),
      ),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: brassDeep,
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

    // CTA principal: latón con texto oscuro (accesible sobre el latón).
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: onBrass,
        minimumSize: const Size(0, 54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    // Variante oscura: carbón con texto de papel.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: charcoal,
        foregroundColor: charcoalInk,
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
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: brassDeep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand,
      foregroundColor: onBrass,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: brand.withValues(alpha: 0.16),
      side: const BorderSide(color: border),
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
      floatingLabelStyle: const TextStyle(color: brassDeep),
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
        backgroundColor: const WidgetStatePropertyAll(surface),
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
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
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
