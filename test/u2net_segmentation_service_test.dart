import 'dart:typed_data';

import 'package:armario_virtual/services/u2net_segmentation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Máscara sintética del tamaño fijo que espera [applyMask]
/// (`U2NetSegmentationService.inputSize` al cuadrado, la resolución de
/// entrada/salida de U2-Netp), ya normalizada a 0..1 como la entrega
/// `_extractMask`: un bloque opaco centrado, a todo el ancho, cuya altura
/// determina [opaqueFraction] del área total. El resto queda en 0
/// (transparente), igual que un mask real fuera del sujeto.
Float32List _mask({required double opaqueFraction}) {
  const size = U2NetSegmentationService.inputSize;
  final mask = Float32List(size * size);
  final opaqueRows = (size * opaqueFraction).round();
  final startRow = (size - opaqueRows) ~/ 2;
  for (var y = startRow; y < startRow + opaqueRows; y++) {
    for (var x = 0; x < size; x++) {
      mask[y * size + x] = 1.0;
    }
  }
  return mask;
}

/// Foto de prueba al mismo tamaño que la máscara (`inputSize`), para que
/// `applyMask` NO tenga que reescalarla: así el recuento de píxeles opacos
/// tras aplicar la máscara es exacto, sin el suavizado de un
/// `copyResize` de por medio.
img.Image _photo() {
  const size = U2NetSegmentationService.inputSize;
  final image = img.Image(width: size, height: size, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(120, 130, 140));
  return image;
}

void main() {
  group('applyMask', () {
    test(
      'máscara ~100% opaca (fondo no separado) lanza en vez de persistir la foto entera sin recortar',
      () {
        final mask = _mask(opaqueFraction: 1.0);
        expect(
          () => applyMask(_photo(), mask),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensaje',
              contains('no logró separar la prenda del fondo'),
            ),
          ),
        );
      },
    );

    test(
      'máscara con separación real (~40% opaco) no lanza y conserva transparencia real',
      () {
        final bytes = applyMask(_photo(), _mask(opaqueFraction: 0.4));

        final decoded = img.decodePng(bytes);
        expect(decoded, isNotNull);

        var transparentCount = 0;
        var opaqueCount = 0;
        for (var y = 0; y < decoded!.height; y++) {
          for (var x = 0; x < decoded.width; x++) {
            final alpha = decoded.getPixel(x, y).a;
            if (alpha <= 0) transparentCount++;
            if (alpha > 127) opaqueCount++;
          }
        }
        // Debe haber de las dos: sin transparencia real sería el mismo bug
        // (foto entera sin recortar) que la guarda de arriba evita.
        expect(transparentCount, greaterThan(0));
        expect(opaqueCount, greaterThan(0));
      },
    );

    test(
      'máscara casi vacía (<1% opaco) sigue lanzando "no encontró ninguna prenda" (guarda existente)',
      () {
        final mask = _mask(opaqueFraction: 0.001);
        expect(
          () => applyMask(_photo(), mask),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensaje',
              contains('no encontró ninguna prenda'),
            ),
          ),
        );
      },
    );
  });
}
