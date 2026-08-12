import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/theme.dart';
import 'package:pos_boutique/core/ui_kit.dart';

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
    test('verde y rojo se leen sobre el fondo oscuro', () {
      expect(contraste(AppColors.success, AppColors.bg), greaterThan(4.5));
      expect(contraste(AppColors.danger, AppColors.bg), greaterThan(4.5));
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
}
