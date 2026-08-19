import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/catalog_sync_service.dart';

/// Lo que pasó el 19 ago 2026: el cliente subió 5 productos desde su equipo y
/// desde otro POS se publicó 1 de prueba. La tienda **no acumula, reemplaza**,
/// así que el catálogo del cliente desapareció de la web.
///
/// El interruptor es por dispositivo. Aquí se prueba lo que sostiene la
/// protección: de fábrica se publica (un equipo nuevo no puede quedarse mudo
/// por accidente), y apagado **no se llega al RPC** — el candado vive en el
/// único punto que lo llama, no en cada pantalla, para que ninguna ruta nueva
/// se lo salte por olvido.
void main() {
  late AppDatabase db;
  late CatalogSyncService sync;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sync = CatalogSyncService(db);
  });
  tearDown(() => db.close());

  test('de fábrica el equipo sí publica', () async {
    expect(await sync.publishEnabled(), isTrue,
        reason: 'un POS recién instalado no debe quedarse mudo');
  });

  test('apagar y prender queda guardado', () async {
    await sync.setPublishEnabled(false);
    expect(await sync.publishEnabled(), isFalse);

    // Otra instancia sobre la misma base: es lo que pasa al reabrir la app.
    expect(await CatalogSyncService(db).publishEnabled(), isFalse,
        reason: 'la decisión tiene que sobrevivir al reinicio');

    await sync.setPublishEnabled(true);
    expect(await sync.publishEnabled(), isTrue);
  });

  test('apagado, publicar se rechaza ANTES de tocar la tienda', () async {
    await sync.setPublishEnabled(false);

    // Sin Supabase inicializado, llegar al RPC lanzaría un error de conexión.
    // Que salga PublishDisabledException prueba que se cortó antes: el candado
    // no depende de que haya red ni de qué pantalla llamó.
    await expectLater(
      sync.publish('el-secreto-que-sea'),
      throwsA(isA<PublishDisabledException>()),
    );
  });

  test('el aviso dice dónde se prende, no solo que falló', () {
    expect(const PublishDisabledException().toString(),
        contains('Publicación de la tienda'));
  });
}
