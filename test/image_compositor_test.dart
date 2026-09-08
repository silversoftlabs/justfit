import 'dart:typed_data';

import 'package:armario_virtual/services/image_compositor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Foto "mejorada" de prueba: un cuadrado azul sólido y opaco, sin alfa.
img.Image _enhancedPhoto(int size) {
  final image = img.Image(width: size, height: size, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(0x20, 0x40, 0x80));
  return image;
}

Uint8List _encode(img.Image image, {bool asPng = true}) =>
    Uint8List.fromList(asPng ? img.encodePng(image) : img.encodeJpg(image));

void main() {
  group('applyCutoutAlpha', () {
    test('alfa=255 en el recorte da alfa≈255 y el RGB de enhanced sin mezclar', () {
      final enhanced = _enhancedPhoto(100);
      final cutout = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(cutout, color: img.ColorRgba8(0, 0, 0, 255));

      final result = img.decodePng(
        applyCutoutAlpha(
          CutoutAlphaParams(enhancedBytes: _encode(enhanced), cutoutBytes: _encode(cutout)),
        ),
      )!;

      final p = result.getPixel(50, 50);
      expect(p.a.toInt(), 255);
      expect(p.r.toInt(), 0x20);
      expect(p.g.toInt(), 0x40);
      expect(p.b.toInt(), 0x80);
    });

    test('alfa=0 en el recorte da alfa=0 en la salida', () {
      final enhanced = _enhancedPhoto(100);
      final cutout = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(cutout, color: img.ColorRgba8(0, 0, 0, 0));

      final result = img.decodePng(
        applyCutoutAlpha(
          CutoutAlphaParams(enhancedBytes: _encode(enhanced), cutoutBytes: _encode(cutout)),
        ),
      )!;

      expect(result.getPixel(50, 50).a.toInt(), 0);
    });

    test('un borde con alfa intermedio se conserva sin umbralizar ni mezclar color', () {
      // Simula el borde suave que entrega el segmentador: alfa=128, sin que
      // eso implique NINGÚN color de fondo detrás del RGB de la prenda.
      final enhanced = _enhancedPhoto(100);
      final cutout = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(cutout, color: img.ColorRgba8(0, 0, 0, 128));

      final result = img.decodePng(
        applyCutoutAlpha(
          CutoutAlphaParams(enhancedBytes: _encode(enhanced), cutoutBytes: _encode(cutout)),
        ),
      )!;

      final p = result.getPixel(50, 50);
      expect(p.a.toInt(), 128);
      // El RGB sigue siendo el de `enhanced` tal cual: nada se ha mezclado
      // hacia ningún color de fondo.
      expect(p.r.toInt(), 0x20);
      expect(p.g.toInt(), 0x40);
      expect(p.b.toInt(), 0x80);
    });

    test('redimensiona el recorte si no coincide con el tamaño de enhanced', () {
      final enhanced = _enhancedPhoto(100);
      final cutout = img.Image(width: 40, height: 40, numChannels: 4);
      img.fill(cutout, color: img.ColorRgba8(0, 0, 0, 255));

      final result = img.decodePng(
        applyCutoutAlpha(
          CutoutAlphaParams(enhancedBytes: _encode(enhanced), cutoutBytes: _encode(cutout)),
        ),
      )!;

      expect(result.width, 100);
      expect(result.height, 100);
    });
  });

  group('renderSoftFallback', () {
    test('el centro del rectángulo del 88%% queda opaco', () {
      final enhanced = _enhancedPhoto(200);

      final result = img.decodePng(
        renderSoftFallback(SoftFallbackParams(enhancedBytes: _encode(enhanced))),
      )!;

      expect(result.getPixel(100, 100).a.toInt(), 255);
    });

    test('fuera del rectángulo del 88%% queda transparente de verdad', () {
      final enhanced = _enhancedPhoto(200);

      final result = img.decodePng(
        renderSoftFallback(SoftFallbackParams(enhancedBytes: _encode(enhanced))),
      )!;

      // Esquina del lienzo: fuera del inset del 88% incluso contando el
      // margen de antialiasing de la esquina redondeada.
      expect(result.getPixel(1, 1).a.toInt(), 0);
    });

    test('el borde de la esquina redondeada conserva antialiasing (alfa intermedio)', () {
      final enhanced = _enhancedPhoto(200);

      final result = img.decodePng(
        renderSoftFallback(SoftFallbackParams(enhancedBytes: _encode(enhanced))),
      )!;

      // insetRatio=0.88 sobre 200px -> lienzo interior de 176px, centrado con
      // offset 12px; radius = 176*0.05 = 8.8px. La banda de antialiasing mide
      // ~1px de ancho y sigue el arco del cuarto de círculo de la esquina, no
      // la diagonal recta lx==ly (esa diagonal avanza sqrt(2)px por paso, más
      // ancho que la propia banda, así que puede saltársela por completo). Se
      // recorre toda la caja de la esquina y basta con que ALGÚN píxel caiga
      // en el arco.
      const offset = 12;
      var foundIntermediate = false;
      for (var ly = 0; ly < 11 && !foundIntermediate; ly++) {
        for (var lx = 0; lx < 11 && !foundIntermediate; lx++) {
          final alpha = result.getPixel(offset + lx, offset + ly).a.toInt();
          if (alpha > 0 && alpha < 255) foundIntermediate = true;
        }
      }
      expect(
        foundIntermediate,
        isTrue,
        reason: 'Ningún píxel de la diagonal de la esquina tiene alfa intermedio',
      );
    });

    test('el RGB dentro del rectángulo es el de la foto, sin mezclar ningún color', () {
      final enhanced = _enhancedPhoto(200);

      final result = img.decodePng(
        renderSoftFallback(SoftFallbackParams(enhancedBytes: _encode(enhanced))),
      )!;

      final p = result.getPixel(100, 100);
      expect(p.r.toInt(), 0x20);
      expect(p.g.toInt(), 0x40);
      expect(p.b.toInt(), 0x80);
    });
  });
}
