import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_boutique/data/local/database.dart';
import 'package:pos_boutique/services/business_card_settings.dart';

/// La tarjeta digital se guarda entera como un solo JSON en `app_settings`
/// (sin migración de esquema Drift). Lo que no puede pasar: perder un campo
/// al recargar, tronar con la base vacía, o volver a subir una foto que ya
/// tiene URL pública.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('de fábrica sale vacía, sin tronar', () async {
    final settings = BusinessCardSettings(db);
    await settings.load();

    expect(settings.data.socials.whatsapp, isEmpty);
    expect(settings.data.shippingFaq, isEmpty);
    expect(settings.data.purchaseSteps, isEmpty);
    expect(settings.data.banners, isEmpty);
    expect(settings.data.coverImagePath, isNull);
    expect(settings.data.loyaltyImagePath, isNull);
  });

  test('guardar y recargar conserva todos los campos, incluidas las listas',
      () async {
    final original = BusinessCardData(
      socials: const CardSocials(
        whatsapp: '5218997034922',
        tiktok: '@shelbycaps',
        facebook: 'facebook.com/shelbycaps',
        instagram: '@shelby.caps',
        locationUrl: 'https://maps.app.goo.gl/xyz',
      ),
      catalogUrl: 'https://shelby-caps.pages.dev',
      coverImagePath: 'business_card_cover.jpg',
      banners: const [
        CardBanner(image: 'business_card_banner_0.jpg', caption: '3x2 en réplicas'),
        CardBanner(image: 'https://cdn.example.com/banner-1.jpg'),
      ],
      shippingNotice: '¡Los envíos salen el mismo día de tu pago!',
      shippingFaq: const [
        FaqItem(q: '¿Qué paquetería utilizamos?', a: 'FedEx, Estafeta o DHL.'),
        FaqItem(q: '¿Aceptan pago contra entrega?', a: 'No.'),
      ],
      purchaseSteps: const [
        'Se realiza una videollamada',
        'Eliges tus modelos',
      ],
      bankTransfer: const BankTransfer(
        bank: 'Santander',
        clabe: '014822606336201992',
        accountNumber: '60633620199',
        holder: 'Shelby Jesus Varela Bocanegra',
      ),
      oxxoDeposit: const OxxoDeposit(bank: 'Santander', cardNumber: '5579070161323632'),
      promotions: const ['10 piezas new era por \$3,500', '3x2 ALO y OC \$1,700'],
      loyaltyText: 'Cada compra suma una casilla; al llegar a 5, la 6ta gorra es gratis.',
      loyaltyImagePath: 'business_card_loyalty.jpg',
    );

    final writer = BusinessCardSettings(db);
    await writer.save(original);

    final reader = BusinessCardSettings(db);
    await reader.load();
    final loaded = reader.data;

    expect(loaded.socials.whatsapp, original.socials.whatsapp);
    expect(loaded.socials.locationUrl, original.socials.locationUrl);
    expect(loaded.catalogUrl, original.catalogUrl);
    expect(loaded.coverImagePath, original.coverImagePath);
    expect(loaded.banners.length, 2);
    expect(loaded.banners[0].image, 'business_card_banner_0.jpg');
    expect(loaded.banners[0].caption, '3x2 en réplicas');
    expect(loaded.banners[1].image, 'https://cdn.example.com/banner-1.jpg');
    expect(loaded.banners[1].caption, isEmpty);
    expect(loaded.shippingNotice, original.shippingNotice);
    expect(loaded.shippingFaq.length, 2);
    expect(loaded.shippingFaq[0].q, original.shippingFaq[0].q);
    expect(loaded.shippingFaq[0].a, original.shippingFaq[0].a);
    expect(loaded.purchaseSteps, original.purchaseSteps);
    expect(loaded.bankTransfer.clabe, original.bankTransfer.clabe);
    expect(loaded.bankTransfer.holder, original.bankTransfer.holder);
    expect(loaded.oxxoDeposit.cardNumber, original.oxxoDeposit.cardNumber);
    expect(loaded.promotions, original.promotions);
    expect(loaded.loyaltyText, original.loyaltyText);
    expect(loaded.loyaltyImagePath, original.loyaltyImagePath);
  });

  test('sin conexión a Supabase, publish() falla limpio y no revienta',
      () async {
    final settings = BusinessCardSettings(db);
    await settings.load();

    final ok = await settings.publish();

    expect(ok, isFalse);
    expect(settings.lastError, isNotNull);
    expect(settings.publishing, isFalse,
        reason: 'el flag de "publicando" no debe quedarse prendido');
  });

  group('isLocalImage — decide si hay que volver a subir la foto', () {
    test('null o vacío: no hay nada que subir', () {
      expect(BusinessCardSettings.isLocalImage(null), isFalse);
      expect(BusinessCardSettings.isLocalImage(''), isFalse);
    });

    test('ruta local (archivo o data URL): sí hay que subirla', () {
      expect(BusinessCardSettings.isLocalImage('business_card_loyalty.jpg'), isTrue);
      expect(BusinessCardSettings.isLocalImage('data:image/jpeg;base64,abc'), isTrue);
    });

    test('ya es una URL pública: no se vuelve a subir', () {
      expect(
        BusinessCardSettings.isLocalImage(
            'https://phyjseekbyitlntmjwwe.supabase.co/storage/v1/object/public/catalog/business-card/loyalty.jpg'),
        isFalse,
      );
    });
  });
}
