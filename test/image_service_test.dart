import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:pos_boutique/services/image_service.dart';

void main() {
  test('optimize redimensiona el lado mayor a <=1000 y recomprime', () {
    // Imagen grande de prueba (2000x1500).
    final big = img.Image(width: 2000, height: 1500);
    img.fill(big, color: img.ColorRgb8(120, 80, 148));
    final bytes = img.encodePng(big); // PNG grande

    final out = ImageService.optimize(bytes);
    expect(out, isNotNull);

    final decoded = img.decodeImage(out!);
    expect(decoded, isNotNull);
    // El lado mayor quedó topado a 1000, con proporción preservada.
    expect(decoded!.width, 1000);
    expect(decoded.height, 750);
  });

  test('optimize no agranda una imagen ya pequeña', () {
    final small = img.Image(width: 300, height: 200);
    img.fill(small, color: img.ColorRgb8(10, 20, 30));
    final out = ImageService.optimize(img.encodePng(small));
    final decoded = img.decodeImage(out!);
    // Bajo el tope: conserva dimensiones (no upscale).
    expect(decoded!.width, 300);
    expect(decoded.height, 200);
  });

  test('optimize devuelve null ante bytes que no son imagen', () {
    final out = ImageService.optimize(
        Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
    expect(out, isNull);
  });

  test('isAsset distingue assets del demo de archivos locales', () {
    expect(ImageService.isAsset('assets/demo/blusa.webp'), isTrue);
    expect(ImageService.isAsset('/data/user/0/app/product_images/x.jpg'),
        isFalse);
  });
}
