import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../services/garment_autocrop_service.dart';
import '../theme/app_palette.dart';
import 'garment_image.dart';

/// Franjas de categoría, de arriba a abajo, en el orden de un flat-lay real:
/// prendas superiores, inferiores, calzado y accesorios (esta última recibe
/// [GarmentCategory.complemento] vía [_bandFor]).
enum _FlatLayBand { top, bottom, footwear, accessory }

/// Cómo compone [OutfitFlatLayView] las prendas de un outfit.
enum OutfitFlatLayLayout {
  /// Franjas horizontales, una por categoría, repartiéndose el ALTO según
  /// `topFlex`/`bottomFlex`/`footwearFlex`. Predecible y sin dependencias
  /// asíncronas: la geometría sale solo de las restricciones del padre.
  bands,

  /// Composición libre estilo flat-lay editorial: cada prenda con su escala,
  /// posición y rotación propias, con solape entre categorías.
  ///
  /// Existe porque el reparto por alto de [bands] penaliza a las prendas
  /// ANCHAS-Y-BAJAS: a igual peso de franja, un par de zapatillas
  /// (aspecto ~1.8) recibe mucho menos alto que un pantalón (~0.7) y se lee
  /// más pequeño aunque las dos llenen su franja al 100%. Aquí cada prenda
  /// se escala por su lado LARGO en vez de por su alto, así que el calzado
  /// gana ancho real y no solo una caja más grande.
  ///
  /// A cambio necesita la relación de aspecto REAL de cada prenda, que llega
  /// de forma asíncrona ([GarmentAutocropCache.aspectRatio]); mientras no
  /// esté, o si falla, se cae a [bands] (ver `_CollageBody`). Por eso las
  /// miniaturas de la rejilla siguen en [bands]: a ~108px de alto la
  /// composición libre pierde legibilidad y no compensa la espera.
  collage,
}

/// Reutiliza [topGarmentCategories] (misma fuente de verdad que
/// `VersatilityService` y el generador rápido de `outfit_screen.dart`) para
/// no duplicar el criterio de "qué cuenta como prenda superior".
_FlatLayBand _bandFor(GarmentCategory category) {
  if (topGarmentCategories.contains(category)) return _FlatLayBand.top;
  if (category == GarmentCategory.pantalon) return _FlatLayBand.bottom;
  if (category == GarmentCategory.calzado) return _FlatLayBand.footwear;
  return _FlatLayBand.accessory;
}

/// Composición tipo flat-lay (foto de producto plana, prendas agrupadas por
/// categoría en franjas horizontales, sin solaparse) de las prendas de un
/// outfit, sobre el mismo lienzo neutro que ya usa la pantalla de "Añadir
/// prenda" (`AppPalette.garmentPhotoBackground`) para las fotos individuales.
///
/// Widget de solo contenido, igual que [GarmentImage]: pinta el lienzo y las
/// prendas, sin radio de esquina, sombra ni borde propios. El envoltorio de
/// tarjeta (`ClipRRect` + `Container` con sombra/borde) lo decide quien lo
/// use, igual que ya hace `_FeaturedSuggestionCard` en `outfit_screen.dart`.
///
/// Llena las restricciones que le dé su padre —requiere un ancestro con
/// altura acotada (`SizedBox`, `AspectRatio`, `Expanded`...), igual que
/// cualquier `Image` con `fit`—, así que sirve tanto para una vista grande de
/// detalle como para una miniatura pequeña sin cambiar el widget.
class OutfitFlatLayView extends StatelessWidget {
  final List<Garment> garments;

  /// Separación entre franjas y, dentro de una franja, entre prendas. Un
  /// único valor para las tres cosas mantiene el espaciado uniforme sin
  /// necesitar tres parámetros distintos.
  final double gap;

  /// Pesos relativos (`Expanded.flex`) de cada franja. Partieron de un
  /// flat-lay de referencia real (top:pantalón:calzado midieron 34%:47%:19%
  /// del alto de las prendas), pero `footwearFlex` se subió por encima de esa
  /// proporción (2 → 3 → 4) porque a ese tamaño el calzado se veía demasiado
  /// pequeño en la pantalla de outfits — MÁS de lo que la proporción por sí
  /// sola explicaba. La causa no era solo el flex: top y pantalón son altos y
  /// estrechos y casi nunca chocan con el ancho disponible de su `Row`
  /// (llenan el 100% del alto de su franja), pero DOS zapatillas anchas y
  /// bajas una junto a otra piden mucho ANCHO, y el `FittedBox(scaleDown)`
  /// que evita que desborden las encogía por ancho antes de agotar el alto
  /// que ya les daba el flex. Por eso, cuando la franja de calzado tiene
  /// exactamente 2 prendas, `_FlatLayBandRow` ya no las pone lado a lado:
  /// las apila con `_StaggeredFootwearPair` (más abajo en este archivo), que
  /// reduce el ancho combinado del par solapándolas y les permite llegar al
  /// 100% del alto de su franja igual que top/pantalón.
  ///
  /// Con esa causa ya resuelta por el escalonado, footwearFlex=4 (30.8% del
  /// total) se comparó de nuevo contra la referencia (19%) en una revisión de
  /// proporciones de `_OutfitDetailSheet` y se veía sobrepeso — el calzado
  /// pesaba casi tanto como el pantalón, que es la prenda con más alto real.
  /// footwearFlex=3 (25%) es el punto intermedio que ya se había probado en
  /// el camino 2 → 3 → 4: se acerca más a la referencia sin perder la
  /// legibilidad del calzado que motivó subirlo en primer lugar.
  /// `accessoryFlex` se queda en su valor original (2), sin seguir a
  /// `footwearFlex`: los complementos son como mucho 2 piezas pequeñas
  /// (gorra, cinturón...), así que no necesitan tanto peso como el calzado.
  final double topFlex;
  final double bottomFlex;
  final double footwearFlex;
  final double accessoryFlex;

  /// Cómo se componen las prendas (ver [OutfitFlatLayLayout]). Por defecto
  /// [OutfitFlatLayLayout.bands], que es lo que quieren las miniaturas; la
  /// hoja de detalle pide [OutfitFlatLayLayout.collage] explícitamente.
  ///
  /// En modo collage los `*Flex` NO se usan: el tamaño de cada prenda sale
  /// de su relación de aspecto real, no del peso de su franja.
  final OutfitFlatLayLayout layout;

  const OutfitFlatLayView({
    super.key,
    required this.garments,
    this.gap = 16,
    this.topFlex = 4,
    this.bottomFlex = 5,
    this.footwearFlex = 3,
    this.accessoryFlex = 2,
    this.layout = OutfitFlatLayLayout.bands,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;

    final byBand = <_FlatLayBand, List<Garment>>{};
    for (final garment in garments) {
      byBand.putIfAbsent(_bandFor(garment.category), () => []).add(garment);
    }

    final flexByBand = <_FlatLayBand, double>{
      _FlatLayBand.top: topFlex,
      _FlatLayBand.bottom: bottomFlex,
      _FlatLayBand.footwear: footwearFlex,
      _FlatLayBand.accessory: accessoryFlex,
    };

    final orderedBands = <(List<Garment>, double, _FlatLayBand)>[];
    for (final band in _FlatLayBand.values) {
      final pieces = byBand[band];
      if (pieces != null && pieces.isNotEmpty) {
        orderedBands.add((pieces, flexByBand[band]!, band));
      }
    }

    if (orderedBands.isEmpty) {
      return ColoredBox(
        color: palette.garmentPhotoBackground,
        child: const SizedBox.expand(),
      );
    }

    final bandsBody = Padding(
      padding: EdgeInsets.all(gap),
      child: Column(
        // El conjunto completo de franjas queda centrado
        // verticalmente en el lienzo, con menos franjas (p.ej. solo
        // top+calzado) o más (con accesorios) igual de equilibrado.
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: gap,
        children: [
          for (final (pieces, flex, band) in orderedBands)
            // `flex` reparte el alto disponible según el peso de
            // CADA franja (top/bottom/footwear/accessory), no a
            // partes iguales: sigue respondiendo al NÚMERO de
            // franjas presentes (las ausentes no restan espacio),
            // pero entre las presentes el reparto ya no es 1:1:1.
            Expanded(
              flex: flex.round(),
              child: _FlatLayBandRow(garments: pieces, gap: gap, band: band),
            ),
        ],
      ),
    );

    return ColoredBox(
      color: palette.garmentPhotoBackground,
      child: layout == OutfitFlatLayLayout.collage
          // `bandsBody` viaja como respaldo ya construido: el collage
          // depende de datos asíncronos y cae a las franjas de siempre si
          // el recorte de alguna prenda falla.
          ? _CollageBody(
              bands: [for (final (pieces, _, band) in orderedBands) (pieces, band)],
              gap: gap,
              bandsFallback: bandsBody,
            )
          : bandsBody,
    );
  }
}

/// Una franja: sus prendas centradas como grupo, cada una escalada por
/// `BoxFit.contain` a la altura disponible de la franja, sin deformarse.
class _FlatLayBandRow extends StatelessWidget {
  final List<Garment> garments;
  final double gap;
  final _FlatLayBand band;

  const _FlatLayBandRow({
    required this.garments,
    required this.gap,
    required this.band,
  });

  @override
  Widget build(BuildContext context) {
    // El par de calzado se escalona (ver _StaggeredFootwearPair) solo
    // cuando la franja tiene EXACTAMENTE 2 prendas: es el caso más común
    // (un par de zapatos) y para el que la geometría del solape está
    // pensada. Con 0/1/3+ prendas, o en cualquier otra franja, se sigue
    // usando el Row centrado de siempre.
    final isStaggerableFootwearPair =
        band == _FlatLayBand.footwear && garments.length == 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        return FittedBox(
          // Red de seguridad para cuando hay MUCHAS prendas en la misma
          // franja: un Row con varios hijos no flexibles no se encoge solo,
          // se desbordaría si no caben lado a lado a su alto natural. Al
          // envolverlo en FittedBox(scaleDown), si el grupo entero no cabe en
          // el ancho disponible se encoge de forma UNIFORME (todas las
          // prendas de esa franja igual de proporción) en vez de desbordar;
          // si sí cabe, se queda a tamaño natural (nunca crece de más). Vale
          // también para el par escalonado de abajo: por muy reducido que
          // quede su ancho combinado, en un lienzo lo bastante estrecho
          // todavía podría no caber.
          fit: BoxFit.scaleDown,
          child: isStaggerableFootwearPair
              ? _StaggeredFootwearPair(
                  front: garments[0],
                  back: garments[1],
                  height: constraints.maxHeight,
                  gap: gap,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: gap,
                  children: [
                    for (final garment in garments)
                      // Solo se fija la ALTURA: Image calcula el ancho a partir de
                      // la relación de aspecto real del PNG cuando solo se le da
                      // una dimensión, así que cada prenda queda a su proporción
                      // original (nunca deformada) y las de distinta forma (una
                      // camiseta ancha, un pantalón estrecho) conviven bien.
                      SizedBox(
                        height: constraints.maxHeight,
                        child: AutocroppedGarment(imagePath: garment.imagePath),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

// Constantes de geometría de _StaggeredFootwearPair, agrupadas aquí para
// poder ajustar el aspecto visual del par sin tocar la lógica de cálculo.
// `_kFootwearOverlapFraction` debe quedarse bien por debajo de 1.0: un
// valor demasiado alto haría que la delantera tape casi por completo a la
// trasera.
const double _kFootwearBackHeightFactor = 0.86;
const double _kFootwearOverlapFraction = 0.32;
const double _kFootwearShadowHeightFactor = 0.12;
const double _kFootwearShadowWidthFactor = 0.92;
const double _kFootwearShadowOpacity = 0.16;

/// Bytes ya recortados de una prenda más su relación de aspecto real
/// (ancho/alto), conocida de antemano vía [GarmentAutocropCache.aspectRatio]
/// para poder calcular geometría exacta sin esperar a que `Image` termine de
/// decodificar de forma asíncrona.
///
/// Lo usan los dos sitios que necesitan saber cuánto ANCHO ocupará una prenda
/// antes de pintarla: el par de calzado escalonado (`_StaggeredFootwearPair`)
/// y la composición libre (`_CollageBody`).
class _GarmentData {
  final Uint8List bytes;
  final double aspect;

  const _GarmentData({required this.bytes, required this.aspect});
}

Future<_GarmentData> _loadGarmentData(String imagePath) async {
  final bytes = await GarmentAutocropCache.cropped(imagePath);
  final aspect = await GarmentAutocropCache.aspectRatio(imagePath);
  return _GarmentData(bytes: bytes, aspect: aspect);
}

/// Geometría exacta (en píxeles, relativa a una esquina inferior izquierda
/// común) del par escalonado: calculada a partir de la relación de aspecto
/// REAL de cada zapatilla, no del ancho asíncrono que reportaría `Image`.
({
  double totalWidth,
  double backLeft,
  double backHeight,
  double frontLeft,
  double shadowLeft,
  double shadowWidth,
  double shadowHeight,
})
_computeFootwearPairGeometry({
  required double frontAspect,
  required double backAspect,
  required double bandHeight,
}) {
  final frontWidth = bandHeight * frontAspect;
  final backHeight = bandHeight * _kFootwearBackHeightFactor;
  final backWidth = backHeight * backAspect;

  // La delantera se solapa con la trasera por una fracción del más
  // estrecho de los dos: reduce el ancho COMBINADO del par (a diferencia
  // de un simple `gap` entre ambas), que es lo que le permite a la
  // delantera llegar a la altura completa de la franja sin toparse con el
  // límite de ancho del `FittedBox` exterior.
  final overlap = _kFootwearOverlapFraction * math.min(frontWidth, backWidth);
  const backLeft = 0.0;
  final frontLeft = math.max(0.0, backWidth - overlap);
  final totalWidth = math.max(backWidth, frontLeft + frontWidth);

  final shadowWidth = totalWidth * _kFootwearShadowWidthFactor;
  final shadowHeight = bandHeight * _kFootwearShadowHeightFactor;

  return (
    totalWidth: totalWidth,
    backLeft: backLeft,
    backHeight: backHeight,
    frontLeft: frontLeft,
    shadowLeft: (totalWidth - shadowWidth) / 2,
    shadowWidth: shadowWidth,
    shadowHeight: shadowHeight,
  );
}

/// Color de la sombra de contacto bajo el par de calzado, derivado del
/// propio color de lienzo (`AppPalette.garmentPhotoBackground`) en vez de
/// un negro fijo: en modo oscuro ese lienzo ya es casi negro
/// (`0xFF1E1E1E`), así que una sombra negra a alpha bajo sería casi
/// invisible. Oscurecer el propio color de fondo en HSL garantiza que la
/// sombra siempre lea "más oscura que el lienzo", en cualquier tema.
Color _footwearShadowColor(Color canvasBackground) {
  final hsl = HSLColor.fromColor(canvasBackground);
  final isDark = hsl.lightness < 0.5;
  final targetLightness = isDark ? hsl.lightness * 0.4 : hsl.lightness * 0.55;
  return hsl.withLightness(targetLightness.clamp(0.0, 1.0)).toColor();
}

/// Par de calzado (exactamente 2 prendas de la franja `footwear`) apilado
/// en diagonal en vez de puesto lado a lado: una zapatilla "delantera" a la
/// altura completa de la franja y otra "trasera" algo más pequeña detrás,
/// solapadas y con una sombra de contacto sutil debajo que las ancla al
/// lienzo. Ver el comentario de `OutfitFlatLayView.footwearFlex` para el
/// porqué: dos zapatillas lado a lado piden más ANCHO del que suele caber,
/// así que el `FittedBox(scaleDown)` de `_FlatLayBandRow` las encogía antes
/// de agotar el alto disponible; solapar el par reduce ese ancho combinado
/// y les permite llegar al 100% del alto de su franja.
///
/// `garments[0]` hace de delantera (pintada encima, a la derecha) y
/// `garments[1]` de trasera (pintada detrás, a la izquierda) — un orden
/// arbitrario pero fijo, sin ninguna semántica de "zapato izquierdo antes
/// que el derecho" en el resto del código.
class _StaggeredFootwearPair extends StatelessWidget {
  final Garment front;
  final Garment back;
  final double height;
  final double gap;

  const _StaggeredFootwearPair({
    required this.front,
    required this.back,
    required this.height,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return FutureBuilder<List<_GarmentData>>(
      future: Future.wait([
        _loadGarmentData(front.imagePath),
        _loadGarmentData(back.imagePath),
      ]),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          // `Future.wait` falla entero en cuanto CUALQUIERA de las dos
          // prendas falla (recorte o decodificación): sin datos completos no
          // hay geometría exacta que calcular, así que se cae al mismo
          // tratamiento de siempre (Row centrado) en vez de un layout a
          // medias con una sola zapatilla.
          if (snapshot.hasError) return _fallbackRow();
          // Aún cargando: hueco en blanco, igual que AutocroppedGarment.
          return const SizedBox.shrink();
        }

        final geometry = _computeFootwearPairGeometry(
          frontAspect: data[0].aspect,
          backAspect: data[1].aspect,
          bandHeight: height,
        );
        final shadowColor = _footwearShadowColor(
          palette.garmentPhotoBackground,
        );

        return SizedBox(
          width: geometry.totalWidth,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: geometry.shadowLeft,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: geometry.shadowWidth,
                    height: geometry.shadowHeight,
                    decoration: ShapeDecoration(
                      gradient: RadialGradient(
                        colors: [
                          shadowColor.withValues(
                            alpha: _kFootwearShadowOpacity,
                          ),
                          shadowColor.withValues(alpha: 0),
                        ],
                      ),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(
                          Radius.elliptical(
                            geometry.shadowWidth / 2,
                            geometry.shadowHeight / 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: geometry.backLeft,
                bottom: 0,
                child: SizedBox(
                  height: geometry.backHeight,
                  child: Image.memory(data[1].bytes, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                left: geometry.frontLeft,
                bottom: 0,
                child: SizedBox(
                  height: height,
                  child: Image.memory(data[0].bytes, fit: BoxFit.contain),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Fallback SEGURO ante un fallo de recorte/decodificación de cualquiera de
  // las dos prendas: exactamente el tratamiento de siempre (Row centrado +
  // AutocroppedGarment normal para ambas). Nunca deja de pintar una prenda
  // por un fallo de esta mejora visual.
  Widget _fallbackRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: gap,
      children: [
        SizedBox(
          height: height,
          child: AutocroppedGarment(imagePath: front.imagePath),
        ),
        SizedBox(
          height: height,
          child: AutocroppedGarment(imagePath: back.imagePath),
        ),
      ],
    );
  }
}

/// Pinta la prenda recortada a su bounding box real de píxeles visibles (ver
/// `GarmentAutocropCache`), para que dos prendas con distinto margen en su
/// foto original ocupen un tamaño relativo comparable dentro del flat-lay.
///
/// Público (no privado a este archivo) porque `daily_outfit_screen.dart` lo
/// reutiliza también para su propio mosaico "Outfit del día"
/// (`_FlatLayGarmentTile`): mismo problema de margen transparente sobrante
/// en la foto guardada, misma solución, sin duplicar la lógica de caché +
/// respaldo entre los dos archivos.
///
/// El recorte se cachea por `imagePath`: reconstruir este widget (p. ej. al
/// generar nuevas sugerencias de IA) no vuelve a decodificar ni recortar la
/// imagen, solo relee el resultado ya cacheado.
///
/// Si el recorte falla (imagen ilegible, formato inesperado...) cae a
/// [GarmentImage] con la foto sin recortar: la composición nunca se queda
/// sin pintar una prenda por un fallo de esta mejora visual.
class AutocroppedGarment extends StatelessWidget {
  final String imagePath;

  /// Cuando no es null, envuelve la imagen resultante en un [Hero] con esta
  /// etiqueta (mismo uso y misma restricción que en [GarmentImage.heroTag]).
  final String? heroTag;

  const AutocroppedGarment({super.key, required this.imagePath, this.heroTag});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: GarmentAutocropCache.cropped(imagePath),
      // Si ya estaba recortada, se pinta desde el primer fotograma (sin el
      // hueco en blanco de un `FutureBuilder` recién montado).
      initialData: GarmentAutocropCache.croppedIfReady(imagePath),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null) {
          return _wrapHero(Image.memory(bytes, fit: BoxFit.contain));
        }
        if (snapshot.hasError) {
          return _wrapHero(
            GarmentImage(imagePath: imagePath, fit: BoxFit.contain),
          );
        }
        // Aún recortando: hueco en blanco en vez de parpadear la versión sin
        // recortar y luego sustituirla, que se vería como un salto de tamaño.
        return const SizedBox.shrink();
      },
    );
  }

  Widget _wrapHero(Widget child) {
    final tag = heroTag;
    if (tag == null) return child;
    return Hero(tag: tag, child: child);
  }
}

// ---------------------------------------------------------------------------
// Composición libre (OutfitFlatLayLayout.collage)
// ---------------------------------------------------------------------------

// Constantes de la composición libre. Todas son RELATIVAS: la escena se
// compone en unidades virtuales sobre `_kCollageBase` y luego un
// `FittedBox(contain)` la ajusta al tamaño real, así que estos números fijan
// proporciones, nunca píxeles finales.
const double _kCollageBase = 100;

/// Separación entre prendas de una misma categoría que NO se solapan.
const double _kCollagePieceGap = 9;

/// Solape horizontal de un par de calzado, como fracción del más estrecho de
/// los dos (mismo criterio que `_kFootwearOverlapFraction` en el modo franjas).
const double _kCollagePairOverlap = 0.18;

/// Solape VERTICAL entre categorías consecutivas, como fracción de la más
/// baja de las dos. Es lo que hace que la escena se lea como un flat-lay
/// apilado en vez de como una lista.
///
/// Es un RANGO, no un valor fijo: la escena se compone a su tamaño natural y
/// luego un `FittedBox(contain)` la encoge para caber, así que el alto es
/// justo lo que limita cuánto pueden crecer las prendas. Con pocas prendas
/// cada categoría trae una sola pieza, las filas salen estrechas y la escena
/// queda más alta que ancha: contra un hueco ancho eso desperdicia parte del
/// ancho y encoge todo sin necesidad. `_composeCollage` sube el solape solo
/// lo justo para que el alto deje de ser el cuello de botella, con
/// [_kCollageBandOverlapMax] como tope para que las prendas no acaben
/// apelotonadas.
///
/// El tope bajó de 0.3 a 0.22 cuando el hueco de la hoja de detalle pasó de
/// cuadrado a rectangular (ver `_kDetailCollageAspect` en `outfit_screen`).
/// Medido con un outfit de 3 prendas en ese hueco nuevo: con 0.22 la escena
/// ya llena el ancho (el ajuste alcanza el aspecto objetivo y se detiene solo,
/// sin llegar al tope), así que subir a 0.3 solo compraba un 5% de tamaño de
/// prenda a cambio de amontonarlas más. El tope antiguo existía para pelear
/// contra un hueco cuadrado que ya no tenemos.
const double _kCollageBandOverlapMin = 0.07;
const double _kCollageBandOverlapMax = 0.22;

/// Desplazamiento horizontal de cada categoría respecto al centro, como
/// fracción de la categoría más ancha: produce el zigzag del boceto.
///
/// También es un rango. Separar las categorías lateralmente NO agranda las
/// prendas (eso solo lo hace acortar la escena), pero mientras el ancho no
/// pase a ser el lado que limita es GRATIS: rellena el hueco lateral que si
/// no quedaría vacío, sin coste de escala. `_composeCollage` ensancha
/// exactamente hasta ese punto de equilibrio, nunca más.
///
/// El tope bajó de 0.45 a 0.38 por el mismo motivo que el del solape: contra
/// el hueco nuevo el ajuste ya no llega ni a 0.38, así que 0.45 era holgura
/// muerta que solo podía dispararse en un hueco raro y leerse como categorías
/// descolocadas en vez de como boceto.
const double _kCollageBandSpreadMin = 0.15;
const double _kCollageBandSpreadMax = 0.38;

/// Inclinación máxima de una prenda, en grados.
const double _kCollageMaxTiltDegrees = 5;

/// Desajuste vertical máximo de una prenda dentro de su categoría, como
/// fracción de su propio alto.
const double _kCollageJitter = 0.04;

const double _kCollageShadowWidthFactor = 0.86;
const double _kCollageShadowHeightFactor = 0.14;

/// Peso del LADO LARGO de cada categoría. Es el corazón de la diferencia con
/// el modo franjas: no reparte alto, fija cuánto debe medir la prenda por su
/// dimensión mayor. El calzado lleva un factor deliberadamente alto porque
/// una prenda ancha-y-baja se lee más pequeña que una alta-y-estrecha del
/// mismo lado largo.
double _collageBandWeight(_FlatLayBand band) {
  switch (band) {
    case _FlatLayBand.top:
      return 0.88;
    case _FlatLayBand.bottom:
      return 1.0;
    case _FlatLayBand.footwear:
      return 1.38;
    case _FlatLayBand.accessory:
      return 0.7;
  }
}

/// Hash estable entre ejecuciones, a diferencia de `String.hashCode` (que en
/// Dart no garantiza el mismo valor entre arranques). Importa porque de aquí
/// salen la inclinación y el desajuste de cada prenda: con `hashCode` una
/// misma prenda podría inclinarse distinto en cada apertura de la app.
int _stableHash(String value) {
  var hash = 0;
  for (final unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

/// Valor determinista en `[-1, 1]` derivado de [seed].
double _deterministicUnit(String seed) {
  return ((_stableHash(seed) % 1000) / 999.0) * 2 - 1;
}

/// Una prenda (o su sombra de contacto) ya colocada en la escena, en
/// coordenadas virtuales con origen en la esquina superior izquierda.
class _CollagePlacement {
  /// `null` en la sombra de contacto, que no es una prenda.
  final Uint8List? bytes;
  final double left;
  final double top;
  final double width;
  final double height;
  final double angle;

  const _CollagePlacement({
    required this.bytes,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.angle,
  });
}

class _Collage {
  final double width;
  final double height;
  final List<_CollagePlacement> placements;

  const _Collage({
    required this.width,
    required this.height,
    required this.placements,
  });
}

/// Una categoría ya resuelta en coordenadas locales: sus prendas colocadas en
/// fila y el tamaño que ocupa el conjunto.
typedef _CollageRow = ({
  double width,
  double height,
  _FlatLayBand band,
  List<_CollagePlacement> items,
});

/// Resuelve cada categoría por separado: tamaño de cada prenda (por su lado
/// LARGO) y su sitio dentro de la fila. No depende ni del solape vertical ni
/// del desplazamiento lateral, así que se calcula UNA vez y se reutiliza en
/// cada iteración del ajuste de `_composeCollage`.
List<_CollageRow> _collageRows({
  required List<(List<Garment>, _FlatLayBand)> bands,
  required List<_GarmentData> data,
}) {
  final rows = <_CollageRow>[];
  var index = 0;

  for (final (pieces, band) in bands) {
    final target = _kCollageBase * _collageBandWeight(band);
    final sized = <({Uint8List bytes, double width, double height, String id})>[];
    for (final garment in pieces) {
      final entry = data[index++];
      // Un aspecto degenerado (0, negativo, NaN) haría explotar la geometría:
      // se degrada a cuadrado en vez de propagar el valor roto.
      final aspect = (entry.aspect.isFinite && entry.aspect > 0) ? entry.aspect : 1.0;
      // El LADO LARGO alcanza el objetivo; el corto sale del aspecto.
      final height = aspect >= 1 ? target / aspect : target;
      sized.add((
        bytes: entry.bytes,
        width: height * aspect,
        height: height,
        id: garment.id,
      ));
    }

    // Un par de calzado se solapa (reduce su ancho combinado y lo hace leer
    // como un par, no como dos zapatos sueltos); el resto se separa.
    final advanceGap = (band == _FlatLayBand.footwear && sized.length == 2)
        ? -_kCollagePairOverlap * sized.map((s) => s.width).reduce(math.min)
        : _kCollagePieceGap;

    final items = <_CollagePlacement>[];
    var cursorX = 0.0;
    var rowHeight = 0.0;
    for (final piece in sized) {
      final jitter = _deterministicUnit('${piece.id}-y') * _kCollageJitter * piece.height;
      final angle =
          _deterministicUnit('${piece.id}-r') * _kCollageMaxTiltDegrees * math.pi / 180;
      items.add(_CollagePlacement(
        bytes: piece.bytes,
        left: cursorX,
        top: jitter,
        width: piece.width,
        height: piece.height,
        angle: angle,
      ));
      cursorX += piece.width + advanceGap;
      rowHeight = math.max(rowHeight, piece.height + jitter.abs());
    }

    rows.add((
      // `cursorX` arrastra un avance de más tras la última prenda.
      width: cursorX - advanceGap,
      height: rowHeight,
      band: band,
      items: items,
    ));
  }

  return rows;
}

/// Apila las categorías ya resueltas con un solape vertical y un
/// desplazamiento lateral concretos, y devuelve la escena con su caja
/// envolvente REAL (la de estas prendas, no un lienzo de tamaño fijo).
///
/// Se llama muchas veces con distintos [overlap]/[spread] mientras
/// `_composeCollage` busca la forma que mejor encaja en el hueco disponible.
_Collage _placeCollageRows(
  List<_CollageRow> rows, {
  required double overlap,
  required double spread,
}) {
  final absolute = <({_CollagePlacement placement, double left, double top})>[];
  var cursorY = 0.0;

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (i > 0) {
      final previous = rows[i - 1];
      cursorY += previous.height - overlap * math.min(previous.height, row.height);
    }
    // Las categorías se desplazan alternativamente a izquierda/derecha del
    // centro. La ÚLTIMA se queda centrada: hace de suelo de la composición
    // (normalmente el calzado).
    final offsetFactor = i == rows.length - 1 ? 0.0 : (i.isEven ? -1.0 : 1.0);
    final rowLeft = -row.width / 2 + offsetFactor * spread;

    // La sombra de contacto va ANTES que las prendas de su categoría para
    // quedar debajo en orden de pintado.
    if (row.band == _FlatLayBand.footwear) {
      final shadowWidth = row.width * _kCollageShadowWidthFactor;
      final shadowHeight = row.height * _kCollageShadowHeightFactor;
      absolute.add((
        placement: _CollagePlacement(
          bytes: null,
          left: 0,
          top: 0,
          width: shadowWidth,
          height: shadowHeight,
          angle: 0,
        ),
        left: rowLeft + (row.width - shadowWidth) / 2,
        top: cursorY + row.height - shadowHeight * 0.45,
      ));
    }

    for (final item in row.items) {
      absolute.add((
        placement: item,
        left: rowLeft + item.left,
        top: cursorY + item.top,
      ));
    }
  }

  // Caja envolvente de la escena, contando que una prenda inclinada ocupa
  // MÁS que su rectángulo sin rotar: sin esto la rotación se saldría del
  // `SizedBox` que mide el `FittedBox` y se vería recortada.
  var minX = double.infinity;
  var maxX = -double.infinity;
  var minY = double.infinity;
  var maxY = -double.infinity;
  for (final entry in absolute) {
    final placement = entry.placement;
    final cos = math.cos(placement.angle).abs();
    final sin = math.sin(placement.angle).abs();
    final boundsWidth = placement.width * cos + placement.height * sin;
    final boundsHeight = placement.width * sin + placement.height * cos;
    final centerX = entry.left + placement.width / 2;
    final centerY = entry.top + placement.height / 2;
    minX = math.min(minX, centerX - boundsWidth / 2);
    maxX = math.max(maxX, centerX + boundsWidth / 2);
    minY = math.min(minY, centerY - boundsHeight / 2);
    maxY = math.max(maxY, centerY + boundsHeight / 2);
  }

  return _Collage(
    width: maxX - minX,
    height: maxY - minY,
    placements: [
      for (final entry in absolute)
        _CollagePlacement(
          bytes: entry.placement.bytes,
          left: entry.left - minX,
          top: entry.top - minY,
          width: entry.placement.width,
          height: entry.placement.height,
          angle: entry.placement.angle,
        ),
    ],
  );
}

/// Busca por bisección el valor de [knob] en `[lo, hi]` con el que la escena
/// deja de ser más ESTRECHA que [targetAspect]. Si ni siquiera en `hi` lo
/// alcanza, devuelve `hi` (el tope); si ya en `lo` la escena es bastante
/// ancha, devuelve `lo` sin tocar nada.
///
/// Sirve para los dos ajustes de [_composeCollage] porque ambos —más solape
/// vertical, más desplazamiento lateral— ensanchan la escena en proporción a
/// su alto de forma monótona.
double _solveCollageKnob({
  required double lo,
  required double hi,
  required double targetAspect,
  required _Collage Function(double knob) layout,
}) {
  bool tooNarrow(double knob) {
    final collage = layout(knob);
    if (collage.height <= 0) return false;
    return collage.width / collage.height < targetAspect;
  }

  if (!tooNarrow(lo)) return lo;
  if (tooNarrow(hi)) return hi;

  var low = lo;
  var high = hi;
  // 18 pasos dejan el resultado muy por debajo de medio píxel virtual, y
  // cada evaluación es aritmética sobre un puñado de prendas.
  for (var i = 0; i < 18; i++) {
    final mid = (low + high) / 2;
    if (tooNarrow(mid)) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return high;
}

/// Compone la escena completa a partir de las prendas agrupadas por categoría
/// y de sus relaciones de aspecto reales, adaptándola al hueco disponible.
///
/// [availableAspect] es `ancho/alto` del espacio real (ya descontado el
/// `gap`). Importa porque la escena se compone a tamaño natural y luego un
/// `FittedBox(contain)` la encoge: si su forma no se parece a la del hueco,
/// una de las dos dimensiones se desperdicia entera. El ajuste va en dos
/// pasos, en este orden y no al revés:
///
///  1. SOLAPE vertical — acorta la escena, que es lo único que de verdad
///     hace crecer a las prendas cuando el alto es el lado que limita. Se
///     sube solo lo necesario y con tope.
///  2. DESPLAZAMIENTO lateral — ensancha la escena. No agranda nada, pero
///     mientras el ancho no pase a limitar es gratis y evita que el hueco se
///     quede medio vacío a los lados.
///
/// Función pura: no toca `BuildContext` ni el árbol de widgets.
_Collage _composeCollage({
  required List<(List<Garment>, _FlatLayBand)> bands,
  required List<_GarmentData> data,
  required double availableAspect,
}) {
  final rows = _collageRows(bands: bands, data: data);
  final widestRow = rows.map((r) => r.width).reduce(math.max);
  final spreadMin = _kCollageBandSpreadMin * widestRow;
  final spreadMax = _kCollageBandSpreadMax * widestRow;

  // Hueco degenerado o sin medir: composición natural, sin ajustar.
  if (!availableAspect.isFinite || availableAspect <= 0) {
    return _placeCollageRows(
      rows,
      overlap: _kCollageBandOverlapMin,
      spread: spreadMin,
    );
  }

  final overlap = _solveCollageKnob(
    lo: _kCollageBandOverlapMin,
    hi: _kCollageBandOverlapMax,
    targetAspect: availableAspect,
    layout: (knob) =>
        _placeCollageRows(rows, overlap: knob, spread: spreadMin),
  );

  final spread = _solveCollageKnob(
    lo: spreadMin,
    hi: spreadMax,
    targetAspect: availableAspect,
    layout: (knob) => _placeCollageRows(rows, overlap: overlap, spread: knob),
  );

  return _placeCollageRows(rows, overlap: overlap, spread: spread);
}

/// Pinta la composición libre. Necesita los bytes recortados y la relación de
/// aspecto de TODAS las prendas antes de poder colocar nada, así que espera a
/// un único `Future.wait`; si cualquiera falla, cae al layout de franjas.
class _CollageBody extends StatelessWidget {
  final List<(List<Garment>, _FlatLayBand)> bands;
  final double gap;
  final Widget bandsFallback;

  const _CollageBody({
    required this.bands,
    required this.gap,
    required this.bandsFallback,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final garments = [for (final (pieces, _) in bands) ...pieces];

    return FutureBuilder<List<_GarmentData>>(
      future: Future.wait(garments.map((g) => _loadGarmentData(g.imagePath))),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          // Sin los datos de TODAS las prendas no hay escena que componer:
          // el layout de franjas de siempre es el respaldo, no un hueco.
          if (snapshot.hasError) return bandsFallback;
          return const SizedBox.expand();
        }

        // La forma del hueco decide cómo se compone la escena, así que hay
        // que medirlo antes: el `LayoutBuilder` da las restricciones que
        // llegan a este widget, y el `Padding` de abajo descuenta `gap` a
        // cada lado.
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth - 2 * gap;
            final availableHeight = constraints.maxHeight - 2 * gap;
            final availableAspect =
                (availableWidth.isFinite &&
                    availableHeight.isFinite &&
                    availableWidth > 0 &&
                    availableHeight > 0)
                ? availableWidth / availableHeight
                // Sin alto o ancho acotados no hay forma a la que adaptarse
                // (el `FittedBox` tampoco tendría contra qué encoger): se
                // compone al natural.
                : double.nan;

            final collage = _composeCollage(
              bands: bands,
              data: data,
              availableAspect: availableAspect,
            );
            if (collage.width <= 0 || collage.height <= 0) return bandsFallback;

            final shadowColor = _footwearShadowColor(
              palette.garmentPhotoBackground,
            );

            return _collageCanvas(
              collage: collage,
              gap: gap,
              shadowColor: shadowColor,
            );
          },
        );
      },
    );
  }

  Widget _collageCanvas({
    required _Collage collage,
    required double gap,
    required Color shadowColor,
  }) {
    return Padding(
      padding: EdgeInsets.all(gap),
      child: FittedBox(
        // La escena se compone en unidades virtuales y se ajusta ENTERA al
        // espacio real: es lo que garantiza que nunca desborde, sea cual sea
        // el número de prendas o sus proporciones.
        fit: BoxFit.contain,
        child: SizedBox(
          width: collage.width,
          height: collage.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final placement in collage.placements)
                Positioned(
                  left: placement.left,
                  top: placement.top,
                  width: placement.width,
                  height: placement.height,
                  child: placement.bytes == null
                      ? IgnorePointer(
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  shadowColor.withValues(
                                    alpha: _kFootwearShadowOpacity,
                                  ),
                                  shadowColor.withValues(alpha: 0),
                                ],
                              ),
                              shape: RoundedSuperellipseBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.elliptical(
                                    placement.width / 2,
                                    placement.height / 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Transform.rotate(
                          angle: placement.angle,
                          child: Image.memory(
                            placement.bytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
