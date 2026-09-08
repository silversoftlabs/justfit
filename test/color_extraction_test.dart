import 'dart:typed_data';

import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/models/garment_options.dart';
import 'package:armario_virtual/services/color_extraction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Lienzo RGBA totalmente transparente, como el que entrega el recorte de
/// U2-Netp antes de pintar la prenda encima.
img.Image _transparentCanvas(int size) =>
    img.Image(width: size, height: size, numChannels: 4);

/// Pinta un rectángulo opaco de color sólido.
void _fillRect(
  img.Image image,
  int x0,
  int y0,
  int x1,
  int y1,
  int r,
  int g,
  int b, {
  int alpha = 255,
}) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      image.setPixelRgba(x, y, r, g, b, alpha);
    }
  }
}

GarmentColorResult _extract(img.Image image, {bool hasAlpha = true}) {
  return extractGarmentColor(
    ColorExtractionParams(
      bytes: Uint8List.fromList(img.encodePng(image)),
      hasAlpha: hasAlpha,
    ),
  );
}

void main() {
  group('extractGarmentColor', () {
    test('una prenda roja sólida sobre fondo transparente se llama Rojo', () {
      final image = _transparentCanvas(200);
      _fillRect(image, 40, 40, 160, 160, 0xC0, 0x39, 0x2B);

      final result = _extract(image);

      expect(result.name, 'Rojo');
      expect(result.isMulticolor, isFalse);
    });

    test('ignora el fondo transparente y no lo mezcla con la prenda', () {
      // El fondo es negro pero con alfa 0: si se contara, el rojo se
      // oscurecería y dejaría de parecerse a la entrada 'Rojo'.
      final image = _transparentCanvas(200);
      _fillRect(image, 0, 0, 200, 200, 0x00, 0x00, 0x00, alpha: 0);
      _fillRect(image, 60, 60, 140, 140, 0xC0, 0x39, 0x2B);

      expect(_extract(image).name, 'Rojo');
    });

    test('el borde semitransparente del recorte no arrastra el color', () {
      // Prenda blanca con un halo verde chillón a media transparencia, que es
      // el patrón que deja una máscara suave sobre un fondo de otro color.
      final image = _transparentCanvas(200);
      _fillRect(image, 40, 40, 160, 160, 0x00, 0xFF, 0x00, alpha: 128);
      _fillRect(image, 55, 55, 145, 145, 0xF8, 0xF8, 0xF6);

      final result = _extract(image);

      expect(result.name, anyOf('Blanco', 'Blanco roto'));
      expect(result.isMulticolor, isFalse);
    });

    test('mitad rojo y mitad blanco se marca como Multicolor', () {
      final image = _transparentCanvas(200);
      _fillRect(image, 20, 20, 180, 100, 0xC0, 0x39, 0x2B);
      _fillRect(image, 20, 100, 180, 180, 0xF8, 0xF8, 0xF6);

      final result = _extract(image);

      expect(result.isMulticolor, isTrue);
      expect(result.name, multicolorName);
    });

    test('un logo pequeño no convierte la prenda en Multicolor', () {
      // Mismo contraste que el caso anterior, pero el segundo color ocupa una
      // fracción mínima: es un estampado, no un segundo color de la prenda.
      final image = _transparentCanvas(200);
      _fillRect(image, 20, 20, 180, 180, 0x1F, 0x2A, 0x44);
      _fillRect(image, 90, 90, 110, 110, 0xF8, 0xF8, 0xF6);

      final result = _extract(image);

      expect(result.isMulticolor, isFalse);
      expect(result.name, 'Azul marino');
    });

    test('un gris cálido cae en un acromático, nunca en Camel', () {
      // Sin la guarda de croma, este tono queda más cerca de 'Camel' en Lab
      // que de cualquier gris, y llamar "camel" a una sudadera gris canta.
      final image = _transparentCanvas(200);
      _fillRect(image, 40, 40, 160, 160, 0xC9, 0xC7, 0xC3);

      final result = _extract(image);

      expect(result.name, isNot('Camel'));
      expect(result.name, isNot('Beige'));
      expect(GarmentPalette.entryFor(result.name)?.isAchromatic, isTrue);
    });

    test('es determinista: la misma foto da siempre el mismo color', () {
      final image = _transparentCanvas(200);
      _fillRect(image, 20, 20, 180, 120, 0x2E, 0x5F, 0xA3);
      _fillRect(image, 20, 120, 180, 180, 0x6B, 0x4A, 0x32);
      final bytes = Uint8List.fromList(img.encodePng(image));

      final first = extractGarmentColor(ColorExtractionParams(bytes: bytes));
      final second = extractGarmentColor(ColorExtractionParams(bytes: bytes));

      expect(second.name, first.name);
      expect(second.rgb, first.rgb);
      expect(second.isMulticolor, first.isMulticolor);
    });

    test('sin canal alfa muestrea la zona central y no el fondo', () {
      // Foto sin recortar: fondo blanco a pantalla completa y la prenda azul
      // en el centro. El recorte central debe quedarse con la prenda.
      final image = img.Image(width: 200, height: 200, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(0xF8, 0xF8, 0xF6));
      _fillRect(image, 40, 40, 160, 160, 0x2E, 0x5F, 0xA3);

      expect(_extract(image, hasAlpha: false).name, 'Azul');
    });

    test('una imagen sin píxeles opacos falla en vez de inventar un color', () {
      expect(
        () => _extract(_transparentCanvas(64)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('migración de temporada', () {
    Map<String, dynamic> garmentJson(String season) => {
          'id': '1',
          'imagePath': 'x.png',
          'category': 'camiseta',
          'color': 'Negro',
          'style': 'casual',
          'season': season,
          'createdAt': '2026-01-01T00:00:00.000',
        };

    test('"entretiempo" del enum antiguo pasa a Todo el año', () {
      // Cubría primavera y otoño a la vez: repartirlo sería inventarse el dato.
      expect(
        Garment.fromJson(garmentJson('entretiempo')).season,
        GarmentSeason.todoElAno,
      );
    });

    test('"todas" del enum antiguo pasa a Todo el año', () {
      expect(
        Garment.fromJson(garmentJson('todas')).season,
        GarmentSeason.todoElAno,
      );
    });

    test('los nombres que no cambiaron se conservan', () {
      expect(Garment.fromJson(garmentJson('verano')).season, GarmentSeason.verano);
      expect(Garment.fromJson(garmentJson('invierno')).season, GarmentSeason.invierno);
    });

    test('los estilos ya guardados siguen siendo válidos', () {
      expect(Garment.fromJson(garmentJson('verano')).style, GarmentStyle.casual);
    });
  });

  group('GarmentPalette', () {
    test('los neutros del armario siguen reconociéndose', () {
      for (final name in ['Negro', 'Blanco', 'Gris', 'Beige', 'Marrón']) {
        expect(GarmentPalette.isNeutral(name), isTrue, reason: name);
      }
    });

    test('un color desconocido no se da por neutro', () {
      expect(GarmentPalette.isNeutral('Fucsia inventado'), isFalse);
    });

    test('Multicolor no compite en el mapeo por distancia', () {
      expect(
        GarmentPalette.matchable.any((e) => e.name == multicolorName),
        isFalse,
      );
    });
  });
}
