import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_boutique/data/local/database.dart';

void main() {
  test('migración v6→v7 crea las tablas de gift card sin perder datos', () async {
    final dir = await Directory.systemTemp.createTemp('pos_mig_v7');
    final file = File(p.join(dir.path, 'test.sqlite'));

    // 1) Base actual (v7) con un cliente que debe sobrevivir.
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.customers).insert(CustomersCompanion.insert(name: 'Ana'));
    await db.close();

    // 2) Simula una base v6: sin tablas de gift card y user_version = 6.
    final raw = sqlite3.open(file.path);
    raw.execute('DROP TABLE IF EXISTS gift_card_transactions');
    raw.execute('DROP TABLE IF EXISTS gift_cards');
    raw.execute('PRAGMA user_version = 6');
    raw.close();

    // 3) Reabrir → corre onUpgrade v6→v7 y crea las tablas.
    db = AppDatabase(NativeDatabase(file));
    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(1));
    expect(customers.single.name, 'Ana');

    // Las tablas nuevas ya son utilizables.
    final cardId = await db.into(db.giftCards).insert(
        GiftCardsCompanion.insert(code: 'GR000000000001'));
    await db.into(db.giftCardTransactions).insert(
        GiftCardTransactionsCompanion.insert(
            cardId: cardId, amountCents: 1000, type: GiftCardTxType.issue));
    final txs = await db.select(db.giftCardTransactions).get();
    expect(txs.single.amountCents, 1000);

    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });
}
