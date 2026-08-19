import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/database.dart';
import 'catalog_sync_service.dart';
import 'image_service.dart';

/// Una pregunta/respuesta de la FAQ de envíos.
class FaqItem {
  const FaqItem({required this.q, required this.a});
  final String q;
  final String a;

  factory FaqItem.fromJson(Map<String, dynamic> j) =>
      FaqItem(q: j['q'] as String? ?? '', a: j['a'] as String? ?? '');
  Map<String, dynamic> toJson() => {'q': q, 'a': a};
}

/// Redes y contacto de la tarjeta. `location` es una liga (Google Maps), no la
/// dirección en texto — la dirección en texto ya vive en `web-catalogo/config.js`.
class CardSocials {
  const CardSocials({
    this.whatsapp = '',
    this.tiktok = '',
    this.facebook = '',
    this.instagram = '',
    this.locationUrl = '',
  });
  final String whatsapp;
  final String tiktok;
  final String facebook;
  final String instagram;
  final String locationUrl;

  factory CardSocials.fromJson(Map<String, dynamic> j) => CardSocials(
        whatsapp: j['whatsapp'] as String? ?? '',
        tiktok: j['tiktok'] as String? ?? '',
        facebook: j['facebook'] as String? ?? '',
        instagram: j['instagram'] as String? ?? '',
        locationUrl: j['locationUrl'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
        'whatsapp': whatsapp,
        'tiktok': tiktok,
        'facebook': facebook,
        'instagram': instagram,
        'locationUrl': locationUrl,
      };

  CardSocials copyWith({
    String? whatsapp,
    String? tiktok,
    String? facebook,
    String? instagram,
    String? locationUrl,
  }) =>
      CardSocials(
        whatsapp: whatsapp ?? this.whatsapp,
        tiktok: tiktok ?? this.tiktok,
        facebook: facebook ?? this.facebook,
        instagram: instagram ?? this.instagram,
        locationUrl: locationUrl ?? this.locationUrl,
      );
}

class BankTransfer {
  const BankTransfer({
    this.bank = '',
    this.clabe = '',
    this.accountNumber = '',
    this.holder = '',
  });
  final String bank;
  final String clabe;
  final String accountNumber;
  final String holder;

  factory BankTransfer.fromJson(Map<String, dynamic> j) => BankTransfer(
        bank: j['bank'] as String? ?? '',
        clabe: j['clabe'] as String? ?? '',
        accountNumber: j['accountNumber'] as String? ?? '',
        holder: j['holder'] as String? ?? '',
      );
  Map<String, dynamic> toJson() =>
      {'bank': bank, 'clabe': clabe, 'accountNumber': accountNumber, 'holder': holder};

  BankTransfer copyWith(
          {String? bank, String? clabe, String? accountNumber, String? holder}) =>
      BankTransfer(
        bank: bank ?? this.bank,
        clabe: clabe ?? this.clabe,
        accountNumber: accountNumber ?? this.accountNumber,
        holder: holder ?? this.holder,
      );
}

class OxxoDeposit {
  const OxxoDeposit({this.bank = '', this.cardNumber = ''});
  final String bank;
  final String cardNumber;

  factory OxxoDeposit.fromJson(Map<String, dynamic> j) => OxxoDeposit(
        bank: j['bank'] as String? ?? '',
        cardNumber: j['cardNumber'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {'bank': bank, 'cardNumber': cardNumber};

  OxxoDeposit copyWith({String? bank, String? cardNumber}) =>
      OxxoDeposit(bank: bank ?? this.bank, cardNumber: cardNumber ?? this.cardNumber);
}

/// Un banner propio de la tarjeta (carrusel superior). Ya **no** son los de la
/// tienda: la tarjeta tiene su propio juego de imágenes. `image` es una ruta
/// local (tablet) o una URL ya publicada; `caption` es opcional y sirve de
/// texto alternativo y de etiqueta para acordarse de cuál es.
class CardBanner {
  const CardBanner({required this.image, this.caption = ''});
  final String image;
  final String caption;

  factory CardBanner.fromJson(Map<String, dynamic> j) => CardBanner(
        image: j['image'] as String? ?? '',
        caption: j['caption'] as String? ?? '',
      );
  Map<String, dynamic> toJson() =>
      {'image': image, if (caption.isNotEmpty) 'caption': caption};

  CardBanner copyWith({String? image, String? caption}) =>
      CardBanner(image: image ?? this.image, caption: caption ?? this.caption);
}

/// Todo el contenido de la tarjeta digital, como un solo bloque. Es contenido
/// de presentación (no se reporta ni se cruza contra nada), así que no hace
/// falta una tabla por sección — un campo más aquí no pide otra migración de
/// esquema, ni local ni en Supabase.
///
/// Las imágenes (portada, banners del carrusel, foto de lealtad) son **propias
/// de la tarjeta**: se guardan como rutas locales aquí y `publish()` las sube
/// al bucket `catalog` bajo `business-card/`. La tarjeta ya no depende de los
/// anuncios de la tienda.
class BusinessCardData {
  const BusinessCardData({
    this.socials = const CardSocials(),
    this.catalogUrl = '',
    this.coverImagePath,
    this.banners = const [],
    this.shippingNotice = '',
    this.shippingFaq = const [],
    this.purchaseSteps = const [],
    this.bankTransfer = const BankTransfer(),
    this.oxxoDeposit = const OxxoDeposit(),
    this.promotions = const [],
    this.loyaltyText = '',
    this.loyaltyImagePath,
  });

  final CardSocials socials;
  final String catalogUrl;

  /// Portada decorativa de arriba (ruta local o URL publicada). Si es `null`,
  /// la página cae a su ilustración de fábrica (`img/portada.svg`).
  final String? coverImagePath;

  /// Carrusel superior, propio de la tarjeta (ya no los de la tienda).
  final List<CardBanner> banners;

  final String shippingNotice;
  final List<FaqItem> shippingFaq;
  final List<String> purchaseSteps;
  final BankTransfer bankTransfer;
  final OxxoDeposit oxxoDeposit;
  final List<String> promotions;
  final String loyaltyText;

  /// Ruta local (tablet) o URL ya publicada (`https://…`). `publish()` sube la
  /// local y la reemplaza por la URL remota — así una segunda publicación no
  /// vuelve a subir la misma foto.
  final String? loyaltyImagePath;

  static const empty = BusinessCardData();

  factory BusinessCardData.fromJson(Map<String, dynamic> j) => BusinessCardData(
        socials: j['socials'] is Map
            ? CardSocials.fromJson(Map<String, dynamic>.from(j['socials'] as Map))
            : const CardSocials(),
        catalogUrl: j['catalogUrl'] as String? ?? '',
        coverImagePath: j['coverImagePath'] as String?,
        banners: (j['banners'] as List?)
                ?.map((e) =>
                    CardBanner.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        shippingNotice: j['shippingNotice'] as String? ?? '',
        shippingFaq: (j['shippingFaq'] as List?)
                ?.map((e) => FaqItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        purchaseSteps:
            (j['purchaseSteps'] as List?)?.map((e) => e as String).toList() ??
                const [],
        bankTransfer: j['bankTransfer'] is Map
            ? BankTransfer.fromJson(Map<String, dynamic>.from(j['bankTransfer'] as Map))
            : const BankTransfer(),
        oxxoDeposit: j['oxxoDeposit'] is Map
            ? OxxoDeposit.fromJson(Map<String, dynamic>.from(j['oxxoDeposit'] as Map))
            : const OxxoDeposit(),
        promotions:
            (j['promotions'] as List?)?.map((e) => e as String).toList() ?? const [],
        loyaltyText: j['loyaltyText'] as String? ?? '',
        loyaltyImagePath: j['loyaltyImagePath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'socials': socials.toJson(),
        'catalogUrl': catalogUrl,
        if (coverImagePath != null) 'coverImagePath': coverImagePath,
        'banners': banners.map((e) => e.toJson()).toList(),
        'shippingNotice': shippingNotice,
        'shippingFaq': shippingFaq.map((e) => e.toJson()).toList(),
        'purchaseSteps': purchaseSteps,
        'bankTransfer': bankTransfer.toJson(),
        'oxxoDeposit': oxxoDeposit.toJson(),
        'promotions': promotions,
        'loyaltyText': loyaltyText,
        if (loyaltyImagePath != null) 'loyaltyImagePath': loyaltyImagePath,
      };

  BusinessCardData copyWith({
    CardSocials? socials,
    String? catalogUrl,
    String? coverImagePath,
    List<CardBanner>? banners,
    String? shippingNotice,
    List<FaqItem>? shippingFaq,
    List<String>? purchaseSteps,
    BankTransfer? bankTransfer,
    OxxoDeposit? oxxoDeposit,
    List<String>? promotions,
    String? loyaltyText,
    String? loyaltyImagePath,
  }) =>
      BusinessCardData(
        socials: socials ?? this.socials,
        catalogUrl: catalogUrl ?? this.catalogUrl,
        coverImagePath: coverImagePath ?? this.coverImagePath,
        banners: banners ?? this.banners,
        shippingNotice: shippingNotice ?? this.shippingNotice,
        shippingFaq: shippingFaq ?? this.shippingFaq,
        purchaseSteps: purchaseSteps ?? this.purchaseSteps,
        bankTransfer: bankTransfer ?? this.bankTransfer,
        oxxoDeposit: oxxoDeposit ?? this.oxxoDeposit,
        promotions: promotions ?? this.promotions,
        loyaltyText: loyaltyText ?? this.loyaltyText,
        loyaltyImagePath: loyaltyImagePath ?? this.loyaltyImagePath,
      );
}

/// Guarda la tarjeta local (`app_settings`, un solo string JSON — mismo
/// patrón que `TaxSettings`/`QuickMenu`, sin migración de esquema Drift) y la
/// publica a Supabase reusando el secreto y el bucket que ya usa el catálogo
/// (`CatalogSyncService`): no se crea una segunda credencial para una tabla.
class BusinessCardSettings extends ChangeNotifier {
  BusinessCardSettings(this._db);
  final AppDatabase _db;

  static const settingKey = 'business_card_json';

  BusinessCardData _data = BusinessCardData.empty;
  BusinessCardData get data => _data;

  DateTime? lastPublishedAt;
  String? lastError;
  bool publishing = false;

  /// `true` si [path] es un archivo/data-URL local que todavía no se subió.
  /// Aparte de `publish()` para poder probarlo sin tocar Supabase.
  static bool isLocalImage(String? path) =>
      path != null && path.isNotEmpty && !path.startsWith('http');

  Future<void> load() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.key.equals(settingKey)))
        .getSingleOrNull();
    final raw = row?.value.trim();
    if (raw == null || raw.isEmpty) {
      _data = BusinessCardData.empty;
    } else {
      try {
        _data = BusinessCardData.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {
        // JSON corrupto (no debería pasar): mejor vacío que tronar la pantalla.
        _data = BusinessCardData.empty;
      }
    }
    notifyListeners();
  }

  /// Guarda SOLO en la tablet. `publish()` es aparte y explícito: esta tarjeta
  /// tiene datos bancarios, así que no se publica sola con un debounce como el
  /// catálogo — el dueño aprieta "Guardar y publicar" cuando ya revisó todo.
  Future<void> save(BusinessCardData data) async {
    _data = data;
    await _db.into(_db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
            key: settingKey, value: jsonEncode(data.toJson())));
    notifyListeners();
  }

  /// Sube la foto de lealtad (si es local) y publica el bloque completo.
  /// Devuelve `true` si funcionó; el detalle del error queda en [lastError].
  Future<bool> publish() async {
    final sync = CatalogSyncService(_db);
    if (!sync.available) {
      lastError = 'Sin conexión a Supabase configurada';
      notifyListeners();
      return false;
    }
    publishing = true;
    notifyListeners();
    try {
      var payload = _data;
      final storage = Supabase.instance.client.storage.from('catalog');

      // Sube una imagen local a `business-card/<remote>` y devuelve su URL
      // pública. Si ya es URL (o no hay bytes) la deja tal cual: una segunda
      // publicación no vuelve a subir la misma foto. Las rutas van por índice
      // (`banner-0.jpg`…), así al re-publicar se sobrescriben en su lugar en vez
      // de acumular archivos.
      Future<String?> upload(String? path, String remote) async {
        if (!isLocalImage(path)) return path;
        final bytes = await ImageService.bytesOf(path!);
        if (bytes == null) return path;
        await storage.uploadBinary(
          remote,
          bytes,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
        return storage.getPublicUrl(remote);
      }

      final newBanners = <CardBanner>[];
      for (var i = 0; i < payload.banners.length; i++) {
        final b = payload.banners[i];
        final url = await upload(b.image, 'business-card/banner-$i.jpg');
        newBanners.add(b.copyWith(image: url ?? b.image));
      }
      payload = payload.copyWith(
        loyaltyImagePath:
            await upload(payload.loyaltyImagePath, 'business-card/loyalty.jpg'),
        coverImagePath:
            await upload(payload.coverImagePath, 'business-card/cover.jpg'),
        banners: newBanners,
      );

      final secret = await sync.ensureSecret();
      await Supabase.instance.client.rpc('publish_business_card', params: {
        'p_secret': secret,
        'p_data': payload.toJson(),
      });

      // La URL remota (si se subió) se queda guardada: no se vuelve a subir
      // la próxima vez que publique.
      await save(payload);
      lastPublishedAt = DateTime.now();
      lastError = null;
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    } finally {
      publishing = false;
      notifyListeners();
    }
  }
}
