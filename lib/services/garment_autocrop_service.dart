import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:image/image.dart' as img;

import 'image_storage.dart';

/// Argumento único de [autocropGarment], pensado para viajar como mensaje de
/// `compute()`: solo tipos primitivos/TypedData.
class AutocropParams {
  /// PNG de la prenda. Idealmente el resultado con transparencia real de
  /// `applyCutoutAlpha`/`renderSoftFallback` (`image_compositor.dart`).
  final Uint8List bytes;

  const AutocropParams({required this.bytes});
}

/// Recorta la imagen de una prenda al bounding box real de sus píxeles
/// visibles (`alpha > 0`), eliminando el margen transparente sobrante.
///
/// Existe porque dos fotos de prendas pueden tener márgenes muy distintos
/// alrededor del recorte (una más centrada, otra con más "aire"), y sin
/// normalizar eso, mostrarlas juntas en `OutfitFlatLayView` las hace parecer
/// de tamaño relativo distinto aunque la prenda real ocupe un espacio
/// comparable. Recortar al contenido real antes de escalar corrige eso.
///
/// Si la imagen no tiene canal alfa útil (prendas guardadas antes de que el
/// recorte tuviera transparencia real, donde `alpha` lee 255 en todo el
/// lienzo) el bounding box abarca la imagen entera: degrada a "sin recorte"
/// en vez de fallar o recortar mal.
///
/// Función pura top-level (requisito de `compute()`) para correr en un
/// isolate secundario. Se recorre la imagen a resolución completa a
/// propósito: a diferencia de `ColorExtractionService` (que solo necesita
/// una muestra estadística del color), un bounding box necesita el píxel
/// visible más extremo exacto, y un margen submuestreado podría recortar de
/// más. El coste solo se paga una vez por imagen: quien llama a esta función
/// (`GarmentAutocropCache`) cachea el resultado por `imagePath`.
Uint8List autocropGarment(AutocropParams params) {
  final image = img.decodeImage(params.bytes);
  if (image == null) {
    throw Exception(
      'No se pudo decodificar la imagen de la prenda para recortarla',
    );
  }

  var minX = image.width;
  var minY = image.height;
  var maxX = -1;
  var maxY = -1;

  final pixel = image.getPixel(0, 0);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.getPixel(x, y, pixel);
      if (pixel.a <= 0) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }

  // Ningún píxel visible (imagen completamente transparente): no hay nada
  // que recortar, se devuelve tal cual en vez de forzar un recorte vacío.
  if (maxX < 0) return params.bytes;

  // Ya ocupa todo el lienzo (o casi): recortar no cambiaría nada visible,
  // así que se evita el coste de reencodar para nada.
  final isFullBleed =
      minX == 0 &&
      minY == 0 &&
      maxX == image.width - 1 &&
      maxY == image.height - 1;
  if (isFullBleed) return params.bytes;

  final cropped = img.copyCrop(
    image,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );

  return Uint8List.fromList(img.encodePng(cropped));
}

/// Caché en memoria (por sesión de la app, sin límite de tamaño) del recorte
/// de [autocropGarment], indexada por `imagePath`.
///
/// Se cachea el `Future`, no solo el resultado ya resuelto: si dos widgets
/// piden el recorte de la MISMA prenda casi a la vez (p. ej. la tarjeta de
/// "Sugerencia del Día" en home y la hoja de detalle mostrando el mismo
/// outfit), comparten un único cálculo en vez de duplicar la decodificación
/// y el recorte. Una vez resuelto, `Future`s ya completados se devuelven al
/// instante en cualquier consulta posterior.
///
/// Sin límite de tamaño: para el orden de decenas/pocos cientos de prendas
/// de un armario típico es asumible; si el catálogo crece mucho, aquí es
/// donde añadir un límite (LRU) más adelante.
///
/// Un fallo (archivo ilegible, imagen corrupta) también se cachea: no se
/// reintenta en peticiones futuras dentro de la misma sesión. Es aceptable
/// porque esos fallos no son transitorios (el archivo no se va a arreglar
/// solo), y el llamador (`OutfitFlatLayView`) ya cae a la imagen sin recortar
/// cuando esto ocurre.
abstract final class GarmentAutocropCache {
  static final Map<String, Future<Uint8List>> _cache = {};
  static final Map<String, Future<double>> _aspectRatioCache = {};

  /// Recortes ya terminados, legibles de forma síncrona. Un `FutureBuilder`
  /// recién montado no puede leer un `Future` ya completado en su primer
  /// fotograma: sin esto, cada vez que se recrea una rejilla (p. ej. al
  /// cambiar de categoría) las prendas parpadeaban un fotograma en blanco.
  static final Map<String, Uint8List> _resolved = {};

  /// El recorte de [imagePath] si ya está listo; `null` si aún no se ha
  /// pedido, sigue en curso o falló.
  static Uint8List? croppedIfReady(String imagePath) => _resolved[imagePath];

  // TEMPORAL (diagnóstico del congelamiento al entrar en Outfits, borrar tras
  // medir): cuenta cuántos recortes hay EN VUELO a la vez y mide cuánto tarda
  // cada uno y el lote completo. `compute()` lanza un isolate nuevo por
  // llamada (no reutiliza uno persistente como U2NetSegmentationService), así
  // que esto separa dos posibles causas del bloqueo: el NÚMERO de isolates
  // lanzados de golpe al construir la pantalla, o el coste de cada recorte
  // individual con fotos reales de cámara (mucho más grandes que las de
  // prueba). Un "lote" es la racha de solicitudes que empieza cuando no había
  // ninguna en vuelo y termina cuando la última de esa racha se resuelve.
  static int _inFlight = 0;
  static int _batchSize = 0;
  static int _batchNumber = 0;
  static Stopwatch? _batchStopwatch;

  static Future<Uint8List> cropped(String imagePath) {
    final cached = _cache[imagePath];
    if (cached != null) return cached;

    if (_inFlight == 0) {
      _batchNumber++;
      _batchSize = 0;
      _batchStopwatch = Stopwatch()..start();
    }
    _inFlight++;
    final orderInBatch = ++_batchSize;
    final batch = _batchNumber;
    debugPrint(
      '[AUTOCROP-METRICS] lote $batch: lanzando recorte #$orderInBatch '
      '($_inFlight en vuelo ahora mismo) — $imagePath',
    );

    final callStopwatch = Stopwatch()..start();
    final future = _compute(imagePath).then((value) {
      _logBatchCompletion(batch, orderInBatch, callStopwatch);
      _resolved[imagePath] = value;
      return value;
    }, onError: (Object e, StackTrace st) {
      _logBatchCompletion(batch, orderInBatch, callStopwatch, error: e);
      Error.throwWithStackTrace(e, st);
    });
    _cache[imagePath] = future;
    return future;
  }

  static void _logBatchCompletion(
    int batch,
    int orderInBatch,
    Stopwatch callStopwatch, {
    Object? error,
  }) {
    _inFlight--;
    final status = error == null ? 'OK' : 'ERROR: $error';
    debugPrint(
      '[AUTOCROP-METRICS] lote $batch: recorte #$orderInBatch terminó '
      '($status) en ${callStopwatch.elapsedMilliseconds}ms '
      '($_inFlight siguen en vuelo, lote lleva '
      '${_batchStopwatch?.elapsedMilliseconds}ms)',
    );
    if (_inFlight == 0) {
      debugPrint(
        '[AUTOCROP-METRICS] === lote $batch TERMINADO: $orderInBatch '
        'recorte(s) disparados de golpe, ${_batchStopwatch?.elapsedMilliseconds}ms '
        'totales hasta que se resolvió el último ===',
      );
    }
  }

  /// Relación de aspecto (ancho/alto) del recorte ya devuelto por [cropped].
  ///
  /// Existe para layouts que necesitan conocer la proporción real de una
  /// prenda ANTES de que `Image` termine de decodificarla de forma
  /// asíncrona (p. ej. calcular a mano la geometría de dos prendas
  /// solapadas en `OutfitFlatLayView`), en vez de dejar que el ancho salga
  /// solo del `RenderImage` una vez pintado.
  ///
  /// Decodifica en un isolate aparte (`compute()`, igual que el propio
  /// autocrop) para no bloquear el hilo de UI, y se cachea por separado de
  /// [cropped]: el coste se paga como mucho una vez por prenda distinta.
  static Future<double> aspectRatio(String imagePath) {
    return _aspectRatioCache.putIfAbsent(imagePath, () async {
      final bytes = await cropped(imagePath);
      // TEMPORAL (diagnóstico del congelamiento, borrar tras medir): segundo
      // compute() independiente del de cropped(), solo para el par de
      // calzado escalonado.
      final sw = Stopwatch()..start();
      final dimensions = await compute(_decodedDimensions, bytes);
      debugPrint(
        '[AUTOCROP-METRICS-ASPECT] aspectRatio de $imagePath resuelto en '
        '${sw.elapsedMilliseconds}ms',
      );
      return dimensions.width / dimensions.height;
    });
  }

  static Future<Uint8List> _compute(String imagePath) async {
    final bytes = await ImageStorage.readBytes(imagePath);
    return compute(autocropGarment, AutocropParams(bytes: bytes));
  }
}

({int width, int height}) _decodedDimensions(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null || decoded.height == 0) {
    throw Exception(
      'No se pudo decodificar la imagen recortada para medir su proporción',
    );
  }
  return (width: decoded.width, height: decoded.height);
}
