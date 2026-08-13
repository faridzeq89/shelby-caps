import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Paleta completa de la app, derivada de **un solo color** que elige el dueño.
///
/// La idea: que pueda poner el color de su marca sin que la app se vuelva
/// ilegible. Él escoge el acento; el resto (el tono claro para texto, el color
/// del texto encima del relleno, el fondo, las superficies) se calcula aquí
/// cumpliendo contraste, en vez de dejarlo a la suerte.
@immutable
class Palette {
  const Palette({
    required this.seed,
    required this.dark,
    required this.brand,
    required this.accent,
    required this.onAccent,
    required this.bar,
    required this.onBar,
    required this.onBarMuted,
    required this.bg,
    required this.surface,
    required this.border,
    required this.ink,
    required this.inkMuted,
    required this.success,
    required this.danger,
  });

  /// El color que eligió el dueño. Se guarda tal cual para poder repintar la
  /// misma paleta al reabrir la app.
  final Color seed;
  final bool dark;

  final Color brand; // relleno de botones
  final Color accent; // texto e iconos de acento
  final Color onAccent; // texto encima del relleno
  final Color bar; // barras de app
  final Color onBar;
  final Color onBarMuted;
  final Color bg; // fondo
  final Color surface; // tarjetas
  final Color border;
  final Color ink; // texto principal
  final Color inkMuted; // texto secundario
  final Color success;
  final Color danger;

  // ---------------------------------------------------------------------------
  // Cálculo de contraste (WCAG). Es lo que hace que cualquier color elegido
  // termine en una pantalla que se lee.
  // ---------------------------------------------------------------------------

  static double _channel(double v) {
    v = v / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
  }

  static double luminance(Color c) =>
      0.2126 * _channel(c.r * 255) +
      0.7152 * _channel(c.g * 255) +
      0.0722 * _channel(c.b * 255);

  static double contrast(Color a, Color b) {
    final la = luminance(a), lb = luminance(b);
    final hi = math.max(la, lb), lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Aclara (o oscurece) [c] lo mínimo necesario para leerse sobre [fondo].
  /// Conserva el tono: mueve la luminosidad en HSL, no el color.
  static Color readableOn(Color c, Color fondo, {double target = 4.5}) {
    if (contrast(c, fondo) >= target) return c;
    final hsl = HSLColor.fromColor(c);
    final fondoClaro = luminance(fondo) > 0.18;
    // Sobre fondo oscuro hay que subir luz; sobre claro, bajarla.
    for (var i = 1; i <= 100; i++) {
      final l = fondoClaro
          ? (hsl.lightness - i * 0.01).clamp(0.0, 1.0)
          : (hsl.lightness + i * 0.01).clamp(0.0, 1.0);
      final probado = hsl.withLightness(l).toColor();
      if (contrast(probado, fondo) >= target) return probado;
      if (l == 0.0 || l == 1.0) break;
    }
    // Si ni el blanco ni el negro alcanzan, se usa el extremo que más contraste.
    return fondoClaro ? Colors.black : Colors.white;
  }

  /// Blanco o negro, el que se lea mejor encima de [fondo].
  static Color inkFor(Color fondo) =>
      contrast(Colors.white, fondo) >= contrast(Colors.black, fondo)
          ? Colors.white
          : Colors.black;

  /// El acento se usa igual sobre el fondo y sobre las tarjetas, así que tiene
  /// que leerse en los dos. Se ajusta contra uno y luego contra el otro: como
  /// ambos van del mismo lado (los dos oscuros, o los dos claros), corregir
  /// para el más exigente no rompe al otro.
  static Color _accentFor(Color seed, Color bg, Color surface) =>
      readableOn(readableOn(seed, bg), surface);

  /// Qué tan distintos se ven dos colores (distancia en RGB, 0–441).
  static double distance(Color a, Color b) => math.sqrt(
        math.pow((a.r - b.r) * 255, 2) +
            math.pow((a.g - b.g) * 255, 2) +
            math.pow((a.b - b.b) * 255, 2),
      );

  /// Elige la primera señal que **no** se confunda con el acento de la marca.
  ///
  /// Si el dueño pone su marca en ámbar, una alarma ámbar deja de avisar; el
  /// mismo problema con un verde marca y el verde de "todo bien". Por eso el
  /// semáforo tiene alternativas y se toma la primera que se distingue.
  static Color _signalAwayFrom(Color accent, List<Color> options) {
    for (final c in options) {
      if (distance(accent, c) > 90) return c;
    }
    return options.reduce((a, b) =>
        distance(accent, a) >= distance(accent, b) ? a : b);
  }

  /// Arma la paleta a partir del color elegido.
  factory Palette.fromSeed(Color seed, {bool dark = true}) {
    final hsl = HSLColor.fromColor(seed);

    if (dark) {
      // Fondo casi negro con un punto del tono elegido: se siente de la marca
      // sin dejar de ser gris oscuro.
      final bg = HSLColor.fromAHSL(1, hsl.hue, 0.08, 0.075).toColor();
      final surface = HSLColor.fromAHSL(1, hsl.hue, 0.07, 0.12).toColor();
      final bar = HSLColor.fromAHSL(1, hsl.hue, 0.10, 0.045).toColor();
      final border = HSLColor.fromAHSL(1, hsl.hue, 0.06, 0.20).toColor();
      const ink = Color(0xFFF4F4F7);
      const inkMuted = Color(0xFFA9A9B4);

      // El relleno del botón es una superficie, no texto: le basta con
      // despegarse del fondo (si no, un color muy oscuro deja el botón de
      // cobrar invisible). El texto encima lo resuelve [inkFor].
      final brand = readableOn(seed, bg, target: 2.2);
      final accent = _accentFor(seed, bg, surface);
      return Palette(
        seed: seed,
        dark: true,
        brand: brand,
        accent: accent,
        onAccent: inkFor(brand),
        bar: bar,
        onBar: ink,
        onBarMuted: inkMuted,
        bg: bg,
        surface: surface,
        border: border,
        ink: ink,
        inkMuted: inkMuted,
        // El semáforo no es marca: es señal. Se elige el que se distinga del
        // acento, porque una alarma del color de la marca no alarma.
        success: _signalAwayFrom(accent, _successDark),
        danger: _signalAwayFrom(accent, _dangerDark),
      );
    }

    final bg = HSLColor.fromAHSL(1, hsl.hue, 0.14, 0.96).toColor();
    final surface = Colors.white;
    final bar = HSLColor.fromAHSL(1, hsl.hue, 0.30, 0.18).toColor();
    final border = HSLColor.fromAHSL(1, hsl.hue, 0.12, 0.85).toColor();
    const ink = Color(0xFF1A1A1E);
    const inkMuted = Color(0xFF5C5C68);
    final brand = readableOn(seed, bg, target: 2.2);
    final accent = _accentFor(seed, bg, surface);
    return Palette(
      seed: seed,
      dark: false,
      brand: brand,
      accent: accent,
      onAccent: inkFor(brand),
      bar: bar,
      onBar: const Color(0xFFF4F4F7),
      onBarMuted: const Color(0xFFB9B9C4),
      bg: bg,
      surface: surface,
      border: border,
      ink: ink,
      inkMuted: inkMuted,
      success: _signalAwayFrom(accent, _successLight),
      danger: _signalAwayFrom(accent, _dangerLight),
    );
  }

  /// Alternativas del semáforo, en orden de preferencia. La primera es la de
  /// siempre; las otras entran solo si la marca se le parece demasiado.
  static const _dangerDark = [
    Color(0xFFFF8A3D), // ámbar
    Color(0xFFFF5B6E), // rojo claro
    Color(0xFFFF4DAE), // magenta
  ];
  static const _successDark = [
    Color(0xFF4FBF87), // verde
    Color(0xFF35C4C4), // turquesa
    Color(0xFF9BD14F), // lima
  ];
  static const _dangerLight = [
    Color(0xFFC2410C),
    Color(0xFFB3123C),
    Color(0xFFA3116B),
  ];
  static const _successLight = [
    Color(0xFF1F7A4C),
    Color(0xFF0F6E6E),
    Color(0xFF4C7A1F),
  ];
}

/// Colores sugeridos. El dueño puede elegir cualquiera con el campo de código,
/// pero tener opciones a un toque evita que tenga que pensar en hexadecimales.
const paletteSuggestions = <({String name, Color color})>[
  (name: 'Vino', color: Color(0xFFA81C22)),
  (name: 'Rojo', color: Color(0xFFD32F2F)),
  (name: 'Latón', color: Color(0xFF9C7A2C)),
  (name: 'Ámbar', color: Color(0xFFE08A1E)),
  (name: 'Verde', color: Color(0xFF2E7D52)),
  (name: 'Turquesa', color: Color(0xFF108F8F)),
  (name: 'Azul', color: Color(0xFF2563C7)),
  (name: 'Índigo', color: Color(0xFF4A47B5)),
  (name: 'Morado', color: Color(0xFF7B3FA8)),
  (name: 'Rosa', color: Color(0xFFC2185B)),
  (name: 'Café', color: Color(0xFF7A4B2A)),
  (name: 'Grafito', color: Color(0xFF4A4A55)),
];
