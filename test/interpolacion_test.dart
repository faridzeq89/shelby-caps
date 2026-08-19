import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia contra un bug que **ya llegó al cliente**: en la ficha del producto
/// el precio se mostraba como `${(data.product.basePriceCents / 100)...}`,
/// texto de código crudo, porque el `$` quedó escapado (`'\$\${...}'`) y Dart
/// dejó de interpolar.
///
/// Es invisible para el analizador —es una cadena válida— y ninguna prueba de
/// lógica lo ve, porque el valor nunca se calcula mal: simplemente no se
/// calcula. Solo se nota mirando la pantalla, y eso ya falló una vez.
///
/// Nada legítimo necesita escribir `\${` en esta app: para mostrar un signo de
/// pesos literal basta `\$` (o `money()`, que es lo que manda el kit).
void main() {
  test('ninguna pantalla imprime código en vez de valores', () {
    final sospechosos = <String>[];
    final lib = Directory('lib');

    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('.g.dart')) continue; // generado por drift
      final lineas = f.readAsLinesSync();
      for (var i = 0; i < lineas.length; i++) {
        // `\${` = un `$` escapado seguido de una llave: la interpolación quedó
        // muerta y el usuario va a leer la expresión tal cual.
        if (lineas[i].contains(r'\${')) {
          sospechosos.add('${f.path}:${i + 1}  ${lineas[i].trim()}');
        }
      }
    }

    expect(sospechosos, isEmpty,
        reason: 'Interpolación rota: el usuario verá el código, no el dato.\n'
            '${sospechosos.join('\n')}');
  });
}
