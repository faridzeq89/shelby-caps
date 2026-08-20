import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/sale_handoff.dart';

void main() {
  group('handoff de cotización a venta', () {
    test('entrega la cotización y se consume una sola vez', () {
      final handoff = SaleHandoff();
      expect(handoff.hasPending, isFalse);

      final quote = Quote(
        id: 7,
        folio: 'C-0007',
        status: QuoteStatus.open,
        subtotalCents: 15000,
        totalCents: 15000,
        createdAt: DateTime(2026, 8, 12),
      );
      handoff.send(quote);

      expect(handoff.hasPending, isTrue);
      expect(handoff.take()!.folio, 'C-0007');
      expect(handoff.take(), isNull,
          reason: 'una cotización se carga al carrito una sola vez');
    });

    test('avisa a quien escuche, que es como el shell cambia de pestaña', () {
      final handoff = SaleHandoff();
      var avisos = 0;
      handoff.addListener(() => avisos++);

      handoff.send(Quote(
        id: 1,
        folio: 'C-0001',
        status: QuoteStatus.open,
        subtotalCents: 100,
        totalCents: 100,
        createdAt: DateTime(2026, 8, 12),
      ));

      expect(avisos, 1);
    });
  });
}
