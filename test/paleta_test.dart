import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/palette.dart';
import 'package:pos_boutique/core/theme.dart';
import 'package:pos_boutique/core/ui_kit.dart';
import 'package:pos_boutique/services/palette_settings.dart';

/// La paleta es vino sobre gris casi negro. El riesgo de un tema oscuro es que
/// algo "se vea bonito" pero no se lea en el mostrador con luz encima, así que
/// aquí el contraste se mide, no se opina.
///
/// Referencia WCAG: 4.5:1 para texto normal, 3:1 para texto grande e iconos.
void main() {
  /// Luminancia relativa según WCAG.
  double lum(Color c) {
    double canal(double v) {
      v = v / 255.0;
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
    }

    return 0.2126 * canal(c.r * 255) +
        0.7152 * canal(c.g * 255) +
        0.0722 * canal(c.b * 255);
  }

  double contraste(Color a, Color b) {
    final la = lum(a), lb = lum(b);
    final claro = math.max(la, lb), oscuro = math.min(la, lb);
    return (claro + 0.05) / (oscuro + 0.05);
  }

  group('texto sobre el fondo', () {
    test('el texto principal se lee de sobra', () {
      expect(contraste(AppColors.ink, AppColors.bg), greaterThan(7),
          reason: 'blanco cálido sobre casi negro');
    });

    test('el texto secundario cumple para texto normal', () {
      expect(contraste(AppColors.inkMuted, AppColors.bg), greaterThan(4.5),
          reason: 'el gris claro es jerarquía, no decoración ilegible');
    });

    test('hay diferencia real entre principal y secundario', () {
      final principal = contraste(AppColors.ink, AppColors.bg);
      final secundario = contraste(AppColors.inkMuted, AppColors.bg);
      expect(principal - secundario, greaterThan(2),
          reason: 'si se parecen, la jerarquía no se nota');
    });
  });

  group('el vino resalta', () {
    test('como texto e iconos sobre el fondo', () {
      expect(contraste(AppColors.accent, AppColors.bg), greaterThan(4.5));
    });

    test('como texto e iconos sobre una tarjeta', () {
      expect(contraste(AppColors.accent, AppColors.surface), greaterThan(4.5));
    });

    test('el relleno lleva texto blanco legible', () {
      expect(contraste(AppColors.onAccent, AppColors.brand), greaterThan(4.5),
          reason: 'es el botón de cobrar: tiene que leerse');
    });
  });

  group('semáforo de estado', () {
    test('verde y alarma se leen sobre el fondo oscuro', () {
      expect(contraste(AppColors.success, AppColors.bg), greaterThan(4.5));
      expect(contraste(AppColors.danger, AppColors.bg), greaterThan(4.5));
    });

    test('la alarma NO se confunde con el acento de la marca', () {
      // Con una marca roja, un error del mismo rojo deja de avisar. La
      // distancia se mide en RGB: si son casi el mismo color, el usuario no
      // distingue "borrar" de "cobrar".
      final a = AppColors.accent, d = AppColors.danger;
      final dist = math.sqrt(
        math.pow((a.r - d.r) * 255, 2) +
            math.pow((a.g - d.g) * 255, 2) +
            math.pow((a.b - d.b) * 255, 2),
      );
      expect(dist, greaterThan(45),
          reason: 'acento y alarma tienen que verse distintos');
    });
  });

  test('la tarjeta se distingue del fondo sin depender de la sombra', () {
    // En oscuro la sombra no se ve; la separación la hace la luz.
    expect(lum(AppColors.surface), greaterThan(lum(AppColors.bg)),
        reason: 'la superficie va un escalón MÁS CLARA que el fondo');
    expect(contraste(AppColors.border, AppColors.bg), greaterThan(1.2),
        reason: 'y el borde tiene que notarse');
  });

  test('la barra ancla la pantalla: es más oscura que el fondo', () {
    expect(lum(AppColors.bar), lessThan(lum(AppColors.bg)));
    expect(contraste(AppColors.onBar, AppColors.bar), greaterThan(7));
  });

  test('el tema queda en modo oscuro y usa la paleta', () {
    final t = buildAppTheme();
    expect(t.colorScheme.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AppColors.bg);
    expect(t.colorScheme.primary, AppColors.brand);
    expect(t.hintColor, AppColors.inkMuted);
  });

  // ---------------------------------------------------------------------------
  // El dueño elige el color desde el menú. Aquí lo que se prueba no es un color
  // bonito, es que **cualquier** color que escoja siga dejando la app legible:
  // si esto falla, un cliente se queda con un punto de venta que no se lee.
  // ---------------------------------------------------------------------------
  group('cualquier color que elija el dueño', () {
    /// Los 12 sugeridos más los casos extremos que rompen paletas: blanco,
    /// negro, un neón saturadísimo y un gris sin tono.
    final semillas = <String, Color>{
      for (final s in paletteSuggestions) s.name: s.color,
      'blanco': const Color(0xFFFFFFFF),
      'negro': const Color(0xFF000000),
      'neón': const Color(0xFF00FF00),
      'amarillo': const Color(0xFFFFFF00),
      'gris': const Color(0xFF808080),
      'casi negro': const Color(0xFF0A0A0A),
    };

    void revisar(Palette p, String nombre, String base) {
      final d = '$nombre ($base)';
      expect(contraste(p.ink, p.bg), greaterThan(7),
          reason: 'texto principal ilegible con $d');
      expect(contraste(p.inkMuted, p.bg), greaterThan(4.5),
          reason: 'texto secundario ilegible con $d');
      expect(contraste(p.ink, p.surface), greaterThan(4.5),
          reason: 'texto sobre tarjeta ilegible con $d');
      expect(contraste(p.accent, p.bg), greaterThan(4.5),
          reason: 'el acento no se lee sobre el fondo con $d');
      expect(contraste(p.accent, p.surface), greaterThan(4.5),
          reason: 'el acento no se lee sobre la tarjeta con $d');
      expect(contraste(p.onAccent, p.brand), greaterThan(4.5),
          reason: 'el botón de cobrar no se lee con $d');
      expect(contraste(p.brand, p.bg), greaterThan(2.1),
          reason: 'el botón se pierde en el fondo con $d');
      expect(contraste(p.onBar, p.bar), greaterThan(7),
          reason: 'la barra superior no se lee con $d');
      expect(contraste(p.onBarMuted, p.bar), greaterThan(4.5),
          reason: 'el subtítulo de la barra no se lee con $d');
      expect(contraste(p.success, p.bg), greaterThan(3),
          reason: 'el verde no se ve con $d');
      expect(contraste(p.danger, p.bg), greaterThan(3),
          reason: 'la alarma no se ve con $d');
      expect(Palette.distance(p.accent, p.danger), greaterThan(45),
          reason: 'la alarma se confunde con la marca con $d');
      expect(Palette.distance(p.accent, p.success), greaterThan(45),
          reason: '"todo bien" se confunde con la marca con $d');
      // La tarjeta se separa del fondo por luz, no por sombra.
      expect(lum(p.surface), isNot(closeTo(lum(p.bg), 0.005)),
          reason: 'la tarjeta se funde con el fondo con $d');
    }

    for (final e in semillas.entries) {
      test('${e.key}: fondo oscuro', () {
        revisar(Palette.fromSeed(e.value), e.key, 'oscuro');
      });
      test('${e.key}: fondo claro', () {
        revisar(Palette.fromSeed(e.value, dark: false), e.key, 'claro');
      });
    }
  });

  test('elegir un color repinta la app entera', () {
    final antes = AppColors.brand;
    try {
      final azul = Palette.fromSeed(const Color(0xFF2563C7));
      AppColors.apply(azul);
      expect(AppColors.brand, azul.brand);
      expect(buildAppTheme().colorScheme.primary, azul.brand,
          reason: 'el tema se arma leyendo AppColors ya aplicado');
      expect(buildAppTheme().scaffoldBackgroundColor, azul.bg);
    } finally {
      // Los colores son globales: si un test los deja pintados, ensucia a los
      // demás.
      AppColors.apply(Palette.fromSeed(const Color(0xFFA81C22)));
      AppColors.brand = antes;
    }
  });

  group('el tema sigue a la paleta, no al revés', () {
    // El 20 ago 2026 el cliente puso el tema en claro y los menús ⋮ se
    // volvieron invisibles: el ColorScheme estaba fijo en Brightness.dark, así
    // que Flutter pintaba de blanco todo icono sin color propio. Estas pruebas
    // miden ese icono contra la tarjeta donde vive, en las dos paletas.
    void conPaleta(bool oscuro, void Function() cuerpo) {
      final antesBrand = AppColors.brand;
      try {
        AppColors.apply(
            Palette.fromSeed(const Color(0xFFA81C22), dark: oscuro));
        cuerpo();
      } finally {
        AppColors.apply(Palette.fromSeed(const Color(0xFFA81C22)));
        AppColors.brand = antesBrand;
      }
    }

    test('el brillo del tema coincide con el fondo elegido', () {
      conPaleta(false, () {
        expect(buildAppTheme().colorScheme.brightness, Brightness.light);
        expect(buildAppTheme().brightness, Brightness.light);
      });
      conPaleta(true, () {
        expect(buildAppTheme().colorScheme.brightness, Brightness.dark);
      });
    });

    test('el icono de un menú se lee sobre la tarjeta, en claro y en oscuro',
        () {
      for (final oscuro in [true, false]) {
        conPaleta(oscuro, () {
          final iconos = buildAppTheme().iconTheme.color!;
          expect(contraste(iconos, AppColors.surface), greaterThan(3),
              reason: 'paleta ${oscuro ? 'oscura' : 'clara'}: el ⋮ tiene que '
                  'verse sobre la tarjeta');
          expect(contraste(iconos, AppColors.bg), greaterThan(3),
              reason: 'y también sobre el fondo');
        });
      }
    });
  });

  test('un color inválido no deja la app sin colores', () {
    expect(PaletteSettings.parseHex('no soy color'), isNull);
    expect(PaletteSettings.parseHex('#A81C22'), const Color(0xFFA81C22));
    expect(PaletteSettings.parseHex('A81C22'), const Color(0xFFA81C22));
    expect(PaletteSettings.toHex(const Color(0xFFA81C22)), '#A81C22');
  });
}
