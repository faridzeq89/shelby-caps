import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/service_note_repository.dart';
import 'package:pos_boutique/features/sales/service_note_ticket.dart';

/// Genera la nota de servicio en PDF para revisarla con los ojos. No es una
/// prueba de comportamiento: es la única forma de comprobar que el papel que se
/// lleva el cliente sale con la forma acordada (bloques, orden, nada cortado).
/// Se salta si no se le da una ruta de salida.
void main() {
  test('vista previa de la nota de servicio', () async {
    final salida = Platform.environment['NOTA_PDF'];
    if (salida == null || salida.isEmpty) {
      markTestSkipped('sin NOTA_PDF: no se genera el PDF');
      return;
    }
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final nota = await ServiceNoteRepository(db).create(
      customerName: 'Juan Pérez',
      customerPhone: '899 123 4567',
      priceCents: 25000,
      notes: 'Mancha en la punta del pie derecho y suela despegada atrás.',
      items: const [
        ServiceItem(
            itemType: ServiceItemType.tenis,
            brand: 'Nike',
            size: '27',
            color: 'Blanco',
            qty: 2),
        ServiceItem(itemType: ServiceItemType.gorra, color: 'Roja'),
      ],
    );
    final bytes = await ServiceNoteTicket.build(nota);
    await File(salida).writeAsBytes(bytes);
    expect(bytes.length, greaterThan(1000));
  });
}
