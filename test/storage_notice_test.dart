import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/core/storage_notice.dart';
import 'package:pos_boutique/core/ui_kit.dart';
import 'package:pos_boutique/data/local/open_db.dart';

/// El aviso de "aquí los cambios se pueden perder" tiene dos obligaciones
/// opuestas: aparecer cuando el navegador no guarda seguro, y **no estorbar
/// nunca** en la tablet, que es donde se vende todos los días.
///
/// Las pruebas corren sobre la implementación nativa (`open_db_native.dart`),
/// así que lo que aquí se verifica es el lado de la tablet. El lado web se
/// comprueba en el navegador: `crossOriginIsolated` debe ser `true` en
/// shelby-pos.pages.dev (ver `web/_headers`).
void main() {
  Widget envolver(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  test('en tablet/PC el guardado es durable por definición', () {
    expect(storageIsDurable, isTrue);
    expect(storageKind, 'archivo');
    expect(storageMissingFeatures, isEmpty);
  });

  testWidgets('en tablet el aviso no ocupa nada', (tester) async {
    await tester.pumpWidget(envolver(const StorageDurabilityNotice()));

    expect(find.byType(WarningBanner), findsNothing);
    expect(
      tester.getSize(find.byType(StorageDurabilityNotice)),
      Size.zero,
      reason: 'no debe empujar el contenido de Inicio ni dejar hueco',
    );
  });

  testWidgets('el banner dice qué pasa y qué hacer', (tester) async {
    await tester.pumpWidget(envolver(const WarningBanner(
      title: 'Aquí los cambios se pueden perder',
      message: 'Usa la tablet mientras tanto.',
    )));

    expect(find.text('Aquí los cambios se pueden perder'), findsOneWidget);
    expect(find.text('Usa la tablet mientras tanto.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
