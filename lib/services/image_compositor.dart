import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Argumento único para [applyCutoutAlpha], pensado para viajar como mensaje
/// de `compute()`: solo tipos primitivos/TypedData.
class CutoutAlphaParams {
  /// Foto ya mejorada (contraste/brillo/enfoque), sin transparencia.
  final Uint8List enhancedBytes;

  /// PNG con canal alfa del recorte (U2-Netp sobre ONNX Runtime): opaco
  /// sobre la prenda, transparente en el resto.
  final Uint8List cutoutBytes;

  const CutoutAlphaParams({
    required this.enhancedBytes,
    required this.cutoutBytes,
  });
}

/// Traslada el canal alfa del recorte a la versión ya mejorada de la foto,
/// SIN mezclar ningún color de fondo: el RGB de cada píxel es el de
/// [CutoutAlphaParams.enhancedBytes] tal cual, y solo el alfa sale del
/// recorte. Es la función que produce el archivo que se PERSISTE como
/// `Garment.imagePath` — con transparencia real, no una ilusión que solo
/// funciona sobre un fondo concreto de la UI.
///
/// El borde suave que ya entrega el segmentador (alfa continuo, no
/// umbralizado a 0/255) se conserva intacto porque aquí no hay ninguna mezcla
/// que lo aplaste: un píxel con alfa=128 en el recorte sigue teniendo
/// alfa=128 en la salida, con el RGB real de la foto debajo.
///
/// Función pura top-level (requisito de `compute()`) para correr en un
/// isolate secundario y no bloquear la UI mientras se procesa una foto de
/// alta resolución.
Uint8List applyCutoutAlpha(CutoutAlphaParams params) {
  final enhanced = img.decodeImage(params.enhancedBytes);
  final cutout = img.decodePng(params.cutoutBytes);
  if (enhanced == null || cutout == null) {
    throw Exception('No se pudieron decodificar las imágenes a combinar');
  }

  // Defensa en profundidad: el segmentador ya debería entregar el recorte al
  // tamaño exacto de la foto original, pero por si redimensiona internamente
  // se fuerza aquí de vuelta al tamaño de la versión mejorada. La cúbica
  // suaviza el alfa igual que suavizaría el color, así que el borde sigue
  // quedando continuo tras el resize.
  final alphaSource = (cutout.width == enhanced.width && cutout.height == enhanced.height)
      ? cutout
      : img.copyResize(
          cutout,
          width: enhanced.width,
          height: enhanced.height,
          interpolation: img.Interpolation.cubic,
        );

  final result = img.Image(width: enhanced.width, height: enhanced.height, numChannels: 4);
  final enhancedPixel = enhanced.getPixel(0, 0);
  final alphaPixel = alphaSource.getPixel(0, 0);
  for (var y = 0; y < enhanced.height; y++) {
    for (var x = 0; x < enhanced.width; x++) {
      enhanced.getPixel(x, y, enhancedPixel);
      alphaSource.getPixel(x, y, alphaPixel);
      result.setPixelRgba(
        x,
        y,
        enhancedPixel.r,
        enhancedPixel.g,
        enhancedPixel.b,
        alphaPixel.a,
      );
    }
  }

  return Uint8List.fromList(img.encodePng(result));
}

/// Argumento único para [renderSoftFallback] (mismo motivo que [CutoutAlphaParams]).
class SoftFallbackParams {
  /// Foto ya mejorada (contraste/brillo/enfoque), sin transparencia.
  final Uint8List enhancedBytes;

  const SoftFallbackParams({required this.enhancedBytes});
}

/// Recorte de respaldo (Nivel 3) cuando la segmentación no encuentra un
/// sujeto claro (foto muy de cerca, sin bordes definidos, todos los motores
/// de recorte fallan...): no hay máscara real, así que en vez de mostrar la
/// foto sin procesar a pantalla completa, se reescala y centra automáticamente
/// como una tarjeta de producto con esquinas redondeadas.
///
/// A diferencia de las versiones con recorte real, aquí NO se puede distinguir
/// prenda de fondo, así que dentro del rectángulo se ve la foto tal cual, con
/// lo que hubiera detrás en la toma: esta función deja de fingir un recorte
/// que no existe, ya no lo disfraza aplanándolo sobre un color neutro. Fuera
/// del rectángulo el resultado es transparente de verdad (alfa=0), reutilizando
/// el mismo cálculo de antialiasing de esquina que antes se usaba para mezclar
/// hacia el color de fondo: ahora ese mismo factor 0..1 se escribe directamente
/// como canal alfa, así que el borde redondeado sigue sin verse dentado.
///
/// El lienzo mantiene la misma resolución que [enhancedBytes] para que el
/// resultado sea consistente con el camino de recorte exitoso.
///
/// Función pura top-level para poder correr en un isolate vía `compute()`.
Uint8List renderSoftFallback(SoftFallbackParams params) {
  final enhanced = img.decodeImage(params.enhancedBytes);
  if (enhanced == null) {
    throw Exception('No se pudo decodificar la foto de la prenda');
  }

  final canvas = img.Image(width: enhanced.width, height: enhanced.height, numChannels: 4);

  // La foto ocupa el 88% del lienzo, centrada, dejando un margen transparente
  // alrededor (efecto "tarjeta"), sin recortar ni distorsionar el encuadre
  // original (misma relación de aspecto, solo se reescala).
  const insetRatio = 0.88;
  final scaledW = (enhanced.width * insetRatio).round();
  final scaledH = (enhanced.height * insetRatio).round();
  final resized = img.copyResize(
    enhanced,
    width: scaledW,
    height: scaledH,
    interpolation: img.Interpolation.cubic,
  );

  final offsetX = (enhanced.width - scaledW) ~/ 2;
  final offsetY = (enhanced.height - scaledH) ~/ 2;
  final radius = (scaledW < scaledH ? scaledW : scaledH) * 0.05;

  final resizedPixel = resized.getPixel(0, 0);
  for (var ly = 0; ly < scaledH; ly++) {
    for (var lx = 0; lx < scaledW; lx++) {
      final nearestX = math.min(lx, scaledW - 1 - lx).toDouble();
      final nearestY = math.min(ly, scaledH - 1 - ly).toDouble();

      double alpha;
      if (nearestX >= radius || nearestY >= radius) {
        alpha = 1.0;
      } else {
        // Distancia al centro del círculo de la esquina redondeada, con una
        // banda de ~1px de antialiasing para que el borde no quede dentado.
        final ddx = radius - nearestX;
        final ddy = radius - nearestY;
        final dist = math.sqrt(ddx * ddx + ddy * ddy);
        alpha = (0.5 - (dist - radius)).clamp(0.0, 1.0);
      }
      if (alpha <= 0) continue;

      resized.getPixel(lx, ly, resizedPixel);
      final cx = offsetX + lx;
      final cy = offsetY + ly;
      canvas.setPixelRgba(
        cx,
        cy,
        resizedPixel.r,
        resizedPixel.g,
        resizedPixel.b,
        (alpha * 255).round(),
      );
    }
  }

  return Uint8List.fromList(img.encodePng(canvas));
}
