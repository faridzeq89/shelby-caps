import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/data/repositories/service_note_repository.dart';
import 'package:pos_boutique/features/sales/service_notes_screen.dart';

/// Los dos campos que el dueño pidió el 20 ago 2026: la nota de servicio nació
/// sin **precio** y sin **notas adicionales**, y son justo los que el mostrador
/// llena con el cliente enfrente. El precio es lo que se le prometió; las notas
/// son en qué estado llegó la pieza, que es lo que evita el pleito al entregar.
void main() {
  late AppDatabase db;
  late ServiceNoteRepository notas;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    notas = ServiceNoteRepository(db);
  });
  tearDown(() => db.close());

  Future<ServiceNote> nota({int? precio, String? texto}) => notas.create(
        customerName: 'Juan Pérez',
        itemType: ServiceItemType.tenis,
        priceCents: precio,
        notes: texto,
      );

  /// Corregir manda SIEMPRE el formulario completo (así funciona la pantalla).
  Future<void> corregir(ServiceNote n,
          {int? precio,
          String? texto,
          String nombre = 'Juan Pérez',
          String? tel,
          String? talla,
          int cantidad = 1}) =>
      notas.updateDetails(n.id,
          customerName: nombre,
          customerPhone: tel,
          size: talla,
          itemType: n.itemType,
          qty: cantidad,
          priceCents: precio,
          notes: texto);

  group('al crear', () {
    test('guarda precio y notas', () async {
      final n = await nota(precio: 25000, texto: 'Mancha en la punta');
      expect(n.priceCents, 25000);
      expect(n.notes, 'Mancha en la punta');
    });

    test('guarda la forma completa que pidió el cliente', () async {
      // Datos del cliente + información del artículo, tal como está el papel.
      final n = await notas.create(
        customerName: '  Juan Pérez ',
        customerPhone: '8997034922',
        brand: 'Nike',
        size: '27',
        color: 'Blanco',
        itemType: ServiceItemType.tenis,
        qty: 2,
        priceCents: 25000,
      );
      expect(n.customerName, 'Juan Pérez', reason: 'recortado');
      expect(n.customerPhone, '8997034922');
      expect(n.brand, 'Nike');
      expect(n.size, '27');
      expect(n.color, 'Blanco');
      expect(n.qty, 2);
    });

    test('la cantidad nunca queda en cero', () async {
      // Una nota de cero piezas no describe nada; el formulario ya lo rechaza,
      // y el repositorio no se confía.
      final n = await notas.create(
          customerName: 'Ana',
          itemType: ServiceItemType.bolsa,
          qty: 0);
      expect(n.qty, 1);
    });

    test('sin precio queda "por definir", no en cero', () async {
      // Cero sería un servicio gratis; nulo es "todavía no lo acordamos". La
      // nota impresa dice "Por definir" y la lista lo marca "sin precio".
      final n = await nota();
      expect(n.priceCents, isNull);
    });

    test('notas en blanco se guardan como nulo, no como cadena vacía',
        () async {
      // Con "" la nota impresa dejaría un bloque "Notas:" vacío.
      final n = await nota(texto: '   ');
      expect(n.notes, isNull);
    });
  });

  group('al corregir', () {
    test('se puede poner el precio después, sin perder el folio', () async {
      final n = await nota();
      await corregir(n, precio: 30000, texto: 'Sin agujetas');
      final v = await notas.byId(n.id);
      expect(v!.priceCents, 30000);
      expect(v.notes, 'Sin agujetas');
      expect(v.folio, n.folio, reason: 'es el papel que tiene el cliente');
    });

    test('se puede volver a dejar el precio por definir', () async {
      final n = await nota(precio: 25000);
      await corregir(n);
      final v = await notas.byId(n.id);
      expect(v!.priceCents, isNull);
      expect(v.notes, isNull);
    });

    test('se corrige el WhatsApp mal tecleado', () async {
      final n = await notas.create(
          customerName: 'Juan Pérez',
          customerPhone: '899123',
          itemType: ServiceItemType.tenis);
      await corregir(n, tel: '8997034922');
      expect((await notas.byId(n.id))!.customerPhone, '8997034922');
    });
  });

  group('leer el precio que se teclea', () {
    test('pesos con y sin decimales', () {
      expect(precioEnCentavos('250'), 25000);
      expect(precioEnCentavos('250.50'), 25050);
      expect(precioEnCentavos(' 1,200 '), 120000);
    });

    test('vacío es "por definir"', () {
      expect(precioEnCentavos(''), isNull);
      expect(precioEnCentavos('   '), isNull);
    });

    test('basura no se traga como cero', () {
      // Si "abc" valiera 0, el mostrador entregaría el servicio gratis sin
      // enterarse. La pantalla avisa en vez de guardar.
      expect(precioEnCentavos('abc'), isNull);
      expect(precioEnCentavos('-50'), isNull);
    });
  });
}
