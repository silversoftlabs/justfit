import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/garment_options.dart';

/// Color dominante de una prenda, calculado a partir de sus píxeles.
class GarmentColorResult {
  /// Nombre de [garmentPalette] al que se ha mapeado el color medido.
  final String name;

  /// Color realmente medido (centroide del grupo dominante), como 0xRRGGBB.
  /// Se conserva aparte del nombre para poder pintar una muestra exacta en la
  /// UI: es la prueba visible de que el dato sale de la foto y no de una
  /// etiqueta elegida a ojo.
  final int rgb;

  /// La prenda tiene varios colores con peso propio (rayas, estampados...) y
  /// no hay un tono único que la represente.
  final bool isMulticolor;

  const GarmentColorResult({
    required this.name,
    required this.rgb,
    required this.isMulticolor,
  });
}

/// Argumento único de [extractGarmentColor], pensado para viajar como mensaje
/// de `compute()`: solo tipos primitivos/TypedData.
class ColorExtractionParams {
  /// Imagen de la prenda. Idealmente el recorte RGBA de
  /// `U2NetSegmentationService`, donde el fondo es transparente.
  final Uint8List bytes;

  /// `true` si [bytes] trae canal alfa utilizable. Cuando es `false` (no hubo
  /// recorte y solo tenemos la foto mejorada) no se puede distinguir prenda de
  /// fondo, así que se muestrea un recorte central; ver [_collectSamples].
  final bool hasAlpha;

  const ColorExtractionParams({required this.bytes, this.hasAlpha = true});
}

/// Parámetros de ajuste del cálculo de color, agrupados y documentados en un
/// único sitio. El trabajo real vive en la función top-level
/// [extractGarmentColor], porque `compute()` exige una función pura de nivel
/// superior.
///
/// A diferencia de `U2NetSegmentationService`, aquí NO hace falta un isolate
/// persistente: aquel mantiene viva una sesión nativa de ONNX Runtime entre
/// fotos, mientras que esto es Dart puro sin estado. El patrón adecuado es el
/// mismo que ya usan `image_enhancer.dart` e `image_compositor.dart`, un
/// `compute()` por foto, que cumple igual el requisito de no bloquear la UI.
abstract final class ColorExtractionService {
  /// Número de grupos del k-means.
  ///
  /// Con k=1 el "color dominante" sería la media de todos los píxeles, y la
  /// media de una camiseta de rayas rojas y blancas es rosa: un color que no
  /// aparece en la prenda. Con k=3, el grupo mayoritario se queda con el color
  /// del tejido mientras los otros dos absorben estampados, logos y sombras.
  static const int clusters = 3;

  /// Techo de píxeles que entran al k-means. Agrupar los 12 Mpx de una foto de
  /// móvil sería inviable en un teléfono; con este orden de magnitud el color
  /// dominante ya es estable.
  static const int maxSamples = 20000;

  /// Alfa mínimo para considerar que un píxel es prenda.
  ///
  /// El borde del recorte de U2-Netp tiene alfa suave, y esos píxeles son una
  /// MEZCLA de prenda y fondo: contarlos arrastra el color medido hacia el
  /// fondo de la foto original. Exigir alfa casi opaco funciona como una
  /// erosión barata del contorno.
  static const int minAlpha = 250;

  /// Un segundo grupo que pese al menos esto y esté lo bastante lejos del
  /// dominante convierte la prenda en 'Multicolor'.
  static const double multicolorMinShare = 0.30;

  /// Distancia en CIE Lab a partir de la cual dos colores se consideran
  /// distintos de verdad y no dos matices del mismo tono.
  static const double multicolorMinDistance = 25.0;

  /// Por debajo de esta croma (raíz de a² + b²) el color se considera
  /// acromático y solo compite contra blancos, grises y negro.
  static const double achromaticMaxChroma = 8.0;
}

/// Calcula el color dominante de la prenda.
///
/// Función pura top-level (requisito de `compute()`) para correr en un isolate
/// secundario y no bloquear la UI mientras se recorre la imagen.
///
/// Es DETERMINISTA: el muestreo es por paso fijo y la inicialización del
/// k-means usa una semilla constante, así que la misma foto da siempre el
/// mismo color.
GarmentColorResult extractGarmentColor(ColorExtractionParams params) {
  final image = img.decodeImage(params.bytes);
  if (image == null) {
    throw Exception('No se pudo decodificar la imagen para calcular el color');
  }

  final samples = _collectSamples(image, hasAlpha: params.hasAlpha);
  if (samples.isEmpty) {
    throw Exception('No quedó ningún píxel de prenda del que extraer el color');
  }

  final clusters = _kMeans(samples, ColorExtractionService.clusters);
  clusters.sort((a, b) => b.count.compareTo(a.count));

  final dominant = clusters.first;
  final total = samples.length ~/ 3;

  // Estampado: un segundo grupo con peso propio Y suficientemente lejos del
  // dominante. Las dos condiciones son necesarias: mucho peso pero cerca es
  // solo el mismo tejido con sombra, y muy lejos pero con cuatro píxeles es
  // una etiqueta o un logo.
  var isMulticolor = false;
  if (clusters.length > 1 &&
      clusters[1].count >= total * ColorExtractionService.multicolorMinShare) {
    final distance = _labDistance(
      dominant.l,
      dominant.a,
      dominant.b,
      clusters[1].l,
      clusters[1].a,
      clusters[1].b,
    );
    isMulticolor = distance > ColorExtractionService.multicolorMinDistance;
  }

  final rgb = _labToRgb(dominant.l, dominant.a, dominant.b);
  final name = isMulticolor
      ? multicolorName
      : _nearestPaletteName(dominant.l, dominant.a, dominant.b);

  return GarmentColorResult(name: name, rgb: rgb, isMulticolor: isMulticolor);
}

// ---------------------------------------------------------------------------
// Muestreo
// ---------------------------------------------------------------------------

/// Recorre la imagen a paso fijo y devuelve los píxeles de prenda ya en Lab,
/// aplanados como `[l0, a0, b0, l1, a1, b1, ...]` en un `Float64List` para no
/// crear un objeto por muestra.
///
/// Cuando no hay canal alfa no se puede saber qué es prenda y qué es fondo, así
/// que se limita el recorrido al 55% central de la foto: es donde queda la
/// prenda en la práctica y evita muestrear las esquinas, que son casi siempre
/// fondo.
Float64List _collectSamples(img.Image image, {required bool hasAlpha}) {
  final int x0, y0, x1, y1;
  if (hasAlpha) {
    x0 = 0;
    y0 = 0;
    x1 = image.width;
    y1 = image.height;
  } else {
    const keep = 0.55;
    final marginX = (image.width * (1 - keep) / 2).round();
    final marginY = (image.height * (1 - keep) / 2).round();
    x0 = marginX;
    y0 = marginY;
    x1 = image.width - marginX;
    y1 = image.height - marginY;
  }

  final area = math.max(1, (x1 - x0) * (y1 - y0));
  // Paso en ambos ejes: la raíz de area/objetivo reparte las muestras de forma
  // homogénea por la superficie en vez de por filas.
  final stride = math.max(
    1,
    math.sqrt(area / ColorExtractionService.maxSamples).floor(),
  );

  final collected = <double>[];
  final pixel = image.getPixel(0, 0);
  for (var y = y0; y < y1; y += stride) {
    for (var x = x0; x < x1; x += stride) {
      image.getPixel(x, y, pixel);
      if (hasAlpha && pixel.a.toInt() < ColorExtractionService.minAlpha) continue;
      _rgbToLab(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), collected);
    }
  }
  return Float64List.fromList(collected);
}

// ---------------------------------------------------------------------------
// k-means en CIE Lab
// ---------------------------------------------------------------------------

/// Un grupo del k-means: su centroide en Lab y cuántas muestras cayeron en él.
class _Cluster {
  double l;
  double a;
  double b;
  int count;

  _Cluster(this.l, this.a, this.b) : count = 0;
}

/// k-means sobre muestras en Lab, con inicialización k-means++ de semilla fija.
///
/// Se trabaja en CIE Lab y no en RGB ni HSV porque es el espacio donde la
/// distancia euclídea se aproxima a la diferencia PERCIBIDA: dos tonos que el
/// ojo ve iguales quedan cerca. En RGB no ocurre (el verde pesa mucho más que
/// el azul) y en HSV tampoco (el tono es circular, así que su resta no mide
/// nada estable cerca del rojo).
List<_Cluster> _kMeans(Float64List samples, int k, {int maxIterations = 20}) {
  final n = samples.length ~/ 3;
  final effectiveK = math.min(k, n);

  // Semilla constante: el resultado debe ser reproducible para la misma foto.
  final random = math.Random(0);
  final centroids = _kMeansPlusPlusInit(samples, n, effectiveK, random);
  final assignments = Int32List(n);

  for (var iteration = 0; iteration < maxIterations; iteration++) {
    var changed = false;

    for (var i = 0; i < n; i++) {
      final l = samples[i * 3];
      final a = samples[i * 3 + 1];
      final b = samples[i * 3 + 2];

      var best = 0;
      var bestDistance = double.infinity;
      for (var c = 0; c < effectiveK; c++) {
        final centroid = centroids[c];
        final distance =
            _labDistanceSquared(l, a, b, centroid.l, centroid.a, centroid.b);
        if (distance < bestDistance) {
          bestDistance = distance;
          best = c;
        }
      }
      if (assignments[i] != best) {
        assignments[i] = best;
        changed = true;
      }
    }

    final sumL = Float64List(effectiveK);
    final sumA = Float64List(effectiveK);
    final sumB = Float64List(effectiveK);
    final counts = Int32List(effectiveK);
    for (var i = 0; i < n; i++) {
      final c = assignments[i];
      sumL[c] += samples[i * 3];
      sumA[c] += samples[i * 3 + 1];
      sumB[c] += samples[i * 3 + 2];
      counts[c]++;
    }

    for (var c = 0; c < effectiveK; c++) {
      centroids[c].count = counts[c];
      // Un grupo vacío se deja donde está: moverlo a un punto al azar rompería
      // el determinismo y no aporta nada, porque al ordenar por tamaño quedará
      // el último de todos modos.
      if (counts[c] == 0) continue;
      centroids[c].l = sumL[c] / counts[c];
      centroids[c].a = sumA[c] / counts[c];
      centroids[c].b = sumB[c] / counts[c];
    }

    // Nadie ha cambiado de grupo: ya ha convergido, seguir iterando daría
    // exactamente el mismo resultado.
    if (!changed) break;
  }

  return centroids;
}

/// Inicialización k-means++: el primer centroide sale de una muestra y cada
/// siguiente se elige con probabilidad proporcional a su distancia al centroide
/// más cercano ya elegido. Reparte mejor los grupos que coger k puntos al azar,
/// que en una prenda lisa tiende a poner los tres centroides sobre el mismo
/// tono y deja el estampado sin representar.
List<_Cluster> _kMeansPlusPlusInit(
  Float64List samples,
  int n,
  int k,
  math.Random random,
) {
  final centroids = <_Cluster>[];
  final first = random.nextInt(n);
  centroids.add(
    _Cluster(samples[first * 3], samples[first * 3 + 1], samples[first * 3 + 2]),
  );

  final distances = Float64List(n);
  while (centroids.length < k) {
    var total = 0.0;
    for (var i = 0; i < n; i++) {
      var nearest = double.infinity;
      for (final centroid in centroids) {
        final d = _labDistanceSquared(
          samples[i * 3],
          samples[i * 3 + 1],
          samples[i * 3 + 2],
          centroid.l,
          centroid.a,
          centroid.b,
        );
        if (d < nearest) nearest = d;
      }
      distances[i] = nearest;
      total += nearest;
    }

    // Todas las muestras coinciden con algún centroide (prenda de un solo
    // color exacto): no hay nada que repartir, se replica el último.
    if (total <= 0) {
      final last = centroids.last;
      centroids.add(_Cluster(last.l, last.a, last.b));
      continue;
    }

    var target = random.nextDouble() * total;
    var chosen = n - 1;
    for (var i = 0; i < n; i++) {
      target -= distances[i];
      if (target <= 0) {
        chosen = i;
        break;
      }
    }
    centroids.add(
      _Cluster(
        samples[chosen * 3],
        samples[chosen * 3 + 1],
        samples[chosen * 3 + 2],
      ),
    );
  }
  return centroids;
}

// ---------------------------------------------------------------------------
// Mapeo a la paleta
// ---------------------------------------------------------------------------

/// Nombre de [garmentPalette] más cercano al color medido.
///
/// Si el color es acromático (croma muy baja) solo compite contra los
/// acromáticos de la paleta: un gris con un punto de calidez está a menos
/// distancia de 'Camel' que de 'Gris claro', y llamar "camel" a una sudadera
/// gris es un fallo mucho más visible que errar el matiz de gris.
String _nearestPaletteName(double l, double a, double b) {
  final chroma = math.sqrt(a * a + b * b);
  final achromatic = chroma < ColorExtractionService.achromaticMaxChroma;

  String? best;
  var bestDistance = double.infinity;
  for (final entry in GarmentPalette.matchable) {
    if (achromatic && !entry.isAchromatic) continue;
    final lab = _entryLab(entry);
    final distance = _labDistanceSquared(l, a, b, lab[0], lab[1], lab[2]);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry.name;
    }
  }
  // `matchable` siempre trae acromáticos, así que el filtro nunca deja la lista
  // vacía; el operador solo cierra el tipo nullable.
  return best ?? garmentColorOptions.first;
}

/// Lab de cada entrada de la paleta, calculado una sola vez.
final Map<String, Float64List> _paletteLabCache = {};

Float64List _entryLab(GarmentColorEntry entry) {
  return _paletteLabCache.putIfAbsent(entry.name, () {
    final out = <double>[];
    _rgbToLab(
      (entry.rgb >> 16) & 0xFF,
      (entry.rgb >> 8) & 0xFF,
      entry.rgb & 0xFF,
      out,
    );
    return Float64List.fromList(out);
  });
}

// ---------------------------------------------------------------------------
// Conversión de color (sRGB <-> CIE Lab, iluminante D65)
// ---------------------------------------------------------------------------

const double _refX = 95.047;
const double _refY = 100.0;
const double _refZ = 108.883;

/// Convierte sRGB de 8 bits a Lab y AÑADE los tres componentes a [out], en vez
/// de devolver una lista nueva: se llama una vez por muestra y crear decenas de
/// miles de listas cortas solo para descartarlas presiona el recolector sin
/// necesidad.
void _rgbToLab(int r, int g, int b, List<double> out) {
  final rl = _srgbToLinear(r / 255.0) * 100.0;
  final gl = _srgbToLinear(g / 255.0) * 100.0;
  final bl = _srgbToLinear(b / 255.0) * 100.0;

  final x = (rl * 0.4124 + gl * 0.3576 + bl * 0.1805) / _refX;
  final y = (rl * 0.2126 + gl * 0.7152 + bl * 0.0722) / _refY;
  final z = (rl * 0.0193 + gl * 0.1192 + bl * 0.9505) / _refZ;

  final fx = _pivotXyz(x);
  final fy = _pivotXyz(y);
  final fz = _pivotXyz(z);

  out.add(116 * fy - 16);
  out.add(500 * (fx - fy));
  out.add(200 * (fy - fz));
}

/// Vuelta de Lab a sRGB de 8 bits empaquetado como 0xRRGGBB, para poder pintar
/// el color medido tal cual en la UI.
int _labToRgb(double l, double a, double b) {
  final fy = (l + 16) / 116;
  final fx = fy + a / 500;
  final fz = fy - b / 200;

  final x = _unpivotXyz(fx) * _refX / 100.0;
  final y = _unpivotXyz(fy) * _refY / 100.0;
  final z = _unpivotXyz(fz) * _refZ / 100.0;

  final r = _linearToSrgb(x * 3.2406 + y * -1.5372 + z * -0.4986);
  final g = _linearToSrgb(x * -0.9689 + y * 1.8758 + z * 0.0415);
  final bb = _linearToSrgb(x * 0.0557 + y * -0.2040 + z * 1.0570);

  return (r << 16) | (g << 8) | bb;
}

double _srgbToLinear(double channel) {
  return channel > 0.04045
      ? math.pow((channel + 0.055) / 1.055, 2.4).toDouble()
      : channel / 12.92;
}

int _linearToSrgb(double channel) {
  final clamped = channel.clamp(0.0, 1.0);
  final value = clamped > 0.0031308
      ? 1.055 * math.pow(clamped, 1 / 2.4).toDouble() - 0.055
      : 12.92 * clamped;
  return (value * 255).round().clamp(0, 255);
}

double _pivotXyz(double value) {
  return value > 0.008856
      ? math.pow(value, 1 / 3).toDouble()
      : (7.787 * value) + 16 / 116;
}

double _unpivotXyz(double value) {
  final cubed = value * value * value;
  return cubed > 0.008856 ? cubed : (value - 16 / 116) / 7.787;
}

double _labDistanceSquared(
  double l1,
  double a1,
  double b1,
  double l2,
  double a2,
  double b2,
) {
  final dl = l1 - l2;
  final da = a1 - a2;
  final db = b1 - b2;
  return dl * dl + da * da + db * db;
}

double _labDistance(
  double l1,
  double a1,
  double b1,
  double l2,
  double a2,
  double b2,
) {
  return math.sqrt(_labDistanceSquared(l1, a1, b1, l2, a2, b2));
}
