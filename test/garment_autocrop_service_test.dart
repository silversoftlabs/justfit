import 'dart:typed_data';

import 'package:armario_virtual/services/garment_autocrop_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _pngWithOpaqueRect(
  int canvasSize,
  int x0,
  int y0,
  int x1,
  int y1,
) {
  final image = img.Image(width: canvasSize, height: canvasSize, numChannels: 4);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      image.setPixelRgba(x, y, 0x20, 0x40, 0x80, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('autocropGarment', () {
    test('recorta al bounding box exacto de los píxeles con alfa > 0', () {
      final bytes = _pngWithOpaqueRect(200, 40, 60, 140, 150);

      final result = autocropGarment(AutocropParams(bytes: bytes));
      final cropped = img.decodePng(result)!;

      expect(cropped.width, 100); // 140 - 40
      expect(cropped.height, 90); // 150 - 60
    });

    test('el contenido recortado conserva el color original, sin mezclar nada', () {
      final bytes = _pngWithOpaqueRect(200, 40, 60, 140, 150);

      final cropped = img.decodePng(autocropGarment(AutocropParams(bytes: bytes)))!;

      final p = cropped.getPixel(10, 10);
      expect(p.r.toInt(), 0x20);
      expect(p.g.toInt(), 0x40);
      expect(p.b.toInt(), 0x80);
      expect(p.a.toInt(), 255);
    });

    test('dos prendas con distinto margen quedan con el mismo tamaño recortado', () {
      // Misma prenda (100x90), una centrada con mucho margen alrededor, otra
      // pegada a una esquina con casi nada de margen: antes del autocrop
      // ocupan una fracción muy distinta de su lienzo; después, el mismo
      // tamaño en píxeles.
      final centered = _pngWithOpaqueRect(400, 150, 155, 250, 245);
      final tight = _pngWithOpaqueRect(120, 10, 15, 110, 105);

      final croppedCentered = img.decodePng(autocropGarment(AutocropParams(bytes: centered)))!;
      final croppedTight = img.decodePng(autocropGarment(AutocropParams(bytes: tight)))!;

      expect(croppedCentered.width, croppedTight.width);
      expect(croppedCentered.height, croppedTight.height);
    });

    test('una imagen completamente transparente se devuelve sin cambios', () {
      final image = img.Image(width: 50, height: 50, numChannels: 4);
      final bytes = Uint8List.fromList(img.encodePng(image));

      final result = autocropGarment(AutocropParams(bytes: bytes));

      expect(result, same(bytes));
    });

    test('sin canal alfa útil (prenda antigua sin transparencia real) no recorta', () {
      // 3 canales: getPixel(...).a siempre lee 255 (opaco en todo el
      // lienzo), así que el bounding box abarca la imagen entera.
      final image = img.Image(width: 80, height: 60, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(0x10, 0x10, 0x10));
      final bytes = Uint8List.fromList(img.encodePng(image));

      final result = autocropGarment(AutocropParams(bytes: bytes));
      final decoded = img.decodeImage(result)!;

      expect(decoded.width, 80);
      expect(decoded.height, 60);
    });
  });

  group('GarmentAutocropCache', () {
    test('recortes fallidos no relanzan una excepción distinta cada vez', () async {
      // Vía indirecta de comprobar que el resultado (éxito o fallo) se
      // cachea: sin caché, cada llamada dispararía una nueva lectura de
      // archivo/objeto Future distinto.
      final first = GarmentAutocropCache.cropped('/ruta/que/no/existe.png');
      final second = GarmentAutocropCache.cropped('/ruta/que/no/existe.png');

      expect(identical(first, second), isTrue);
      await expectLater(first, throwsA(anything));
    });
  });
}
