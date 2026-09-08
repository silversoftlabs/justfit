import 'dart:math';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_enums.dart';
import '../models/garment.dart';
import '../models/garment_options.dart';
import '../models/outfit_filters.dart';
import '../models/tipo_prenda.dart';
import 'outfit_recommendation_service.dart';

/// Combina las prendas del armario en outfits válidos con un motor de reglas
/// local: sin red, sin IA, sin coste. Cruza categoría, color, estilo y
/// temporada de cada prenda para decidir qué combinaciones tienen sentido, y
/// usa los chips de contexto (ocasión/clima) solo como preferencia de orden,
/// nunca como filtro duro. Lo usa `OutfitRecommendationService`, que antes
/// delegaba esta generación en Gemini.
///
/// ## Sistema de capas (layering) de la parte superior
///
/// A diferencia del resto de la app (que trata camiseta/sudadera/chaqueta
/// como un único hueco indiferenciado vía `topGarmentCategories`), este motor
/// SÍ distingue tres capas formales (ver [GarmentLayer]) para poder
/// combinarlas entre sí en vez de elegir solo una:
///
///  - **Base** (`GarmentLayer.base`): camisetas, tops, camisas, polos —
///    cualquier prenda de [GarmentCategory.camiseta].
///  - **Intermedia** (`GarmentLayer.mid`): sudaderas, jerséis/cárdigans
///    (ambos representados como [GarmentCategory.sudadera] — ver
///    `DailyOutfitCategoryOption.sudaderaJersey`) y chalecos. El chaleco
///    normalmente se guarda como [GarmentCategory.chaqueta] (abrigo) en el
///    modelo de datos, pero por función real de capa es un abrigo ligero:
///    [_layerOf] lo reclasifica a `mid` por su `tipoPrendaId` (ver
///    [_midTipoPrendaIds]) sin tocar `models/garment.dart`.
///  - **Exterior** (`GarmentLayer.outer`): chaquetas, abrigos, cazadoras,
///    cortavientos, blazers — el resto de [GarmentCategory.chaqueta].
///
/// [_buildUpperCombos] construye las combinaciones válidas de parte
/// superior, todas ancladas en una capa base salvo la exterior sola (que ya
/// existía en la app antes de este sistema formal y se conserva por
/// compatibilidad):
///
///  - Capa base sola (p. ej. camiseta) — Opción A.
///  - Capa base + capa intermedia (p. ej. camiseta + jersey/sudadera), SIN
///    exterior — Opción B.
///  - Capa base + capa exterior (p. ej. camisa + chaqueta), sin intermedia —
///    Opción C.
///  - Capa base + intermedia + exterior, las tres a la vez (p. ej. camiseta +
///    sudadera + chaqueta).
///  - Capa exterior sola (p. ej. chaqueta), sin base — comportamiento
///    preexistente, no forma parte del sistema de capas formal (que exige
///    base) pero se mantiene por compatibilidad con outfits ya soportados.
///
/// Una capa intermedia NUNCA aparece sin una capa base en el mismo combo
/// (ni sola, ni junto a una exterior sin base) en el modo normal: eso
/// modelaría llevar solo el jersey pegado a la piel sin nada debajo digno de
/// "capa base", que este motor no considera un outfit completo. La única
/// excepción es cuando esa prenda intermedia es la que el usuario fijó
/// explícitamente (`lockedMatch`, ver [generate]): ahí sí puede aparecer
/// sola si no hay ninguna base disponible, aunque el motor sigue intentando
/// primero encontrarle una base compatible (ver el comentario de
/// [_scoreLocked] sobre el bonus de completitud).
class OutfitMatchingService {
  /// Pares de estilo compatibles entre sí además de la igualdad. `deportivo`
  /// nunca se mezcla con `formal`/`elegante`.
  static const _compatibleStyles = {
    GarmentStyle.casual: {GarmentStyle.deportivo, GarmentStyle.trabajo},
    GarmentStyle.trabajo: {GarmentStyle.casual, GarmentStyle.formal},
    GarmentStyle.formal: {GarmentStyle.elegante, GarmentStyle.trabajo},
    GarmentStyle.elegante: {GarmentStyle.formal},
    GarmentStyle.deportivo: {GarmentStyle.casual},
  };

  /// Pares de family de color considerados combinaciones clásicas entre dos
  /// colores NO neutros (misma family o cualquiera neutro ya combina sin
  /// pasar por esta tabla).
  static const _classicColorFamilyPairs = {
    ('Azul', 'Rojo'),
    ('Azul', 'Amarillo'),
    ('Rosa', 'Verde'),
    ('Naranja', 'Azul'),
  };

  static const _titleTemplates = ['Look', 'Combinación', 'Outfit', 'Propuesta'];

  /// `TipoPrenda.id` (ver `models/tipo_prenda.dart`) que nunca deben
  /// aparecer en un outfit de ocasión [OutfitOccasion.deporte], a diferencia
  /// del resto de la ocasión/clima (ver [_targetStyle]/[_targetSeason]), que
  /// solo puntúan como preferencia. Aquí SÍ es un filtro duro: un vaquero
  /// puesto como "deportivo" por el usuario al añadirlo seguiría sin ser
  /// deporte de verdad, así que se excluye por tipo de prenda
  /// independientemente de [Garment.style].
  ///
  ///  - `vaqueros`: vaqueros/jeans, mezclilla/denim.
  ///  - `chino_vestir`: pantalón de vestir/rígido.
  ///  - `vestido`, `traje_completo`: vestido de vestir y traje formal
  ///    (prendas de una sola pieza, ver `TipoPrendaMapping.categoria`).
  ///  - `blazer_americana`: el único tipo de "abrigo" del catálogo que es
  ///    claramente de vestir. `abrigo_parka`/`chaqueta_cazadora`/`chaleco`
  ///    se dejan fuera de esta lista a propósito: son prendas funcionales/
  ///    casuales que sí pueden combinarse con un look deportivo en frío.
  ///  - `zapatos_formales`: zapato de vestir. `botas`/`botines`/`sandalias`
  ///    se dejan fuera: unas botas o unas sandalias sí encajan en según qué
  ///    deporte/actividad; `zapatillas` es el calzado deportivo por excelencia.
  static const _sportIncompatibleTipoPrendaIds = {
    'vaqueros',
    'chino_vestir',
    'vestido',
    'traje_completo',
    'blazer_americana',
    'zapatos_formales',
  };

  /// Una prenda SIN `tipoPrendaId` (guardada antes de que existiera ese
  /// campo, ver `Garment.tipoPrendaId`) no se puede distinguir por tipo
  /// granular: se conserva sin filtrar, mismo criterio conservador que ya
  /// usa `OutfitRecommendationService.filterGarmentsByTemperature`.
  static bool _isSportCompatible(Garment garment) {
    final id = garment.tipoPrendaId;
    if (id == null) return true;
    return !_sportIncompatibleTipoPrendaIds.contains(id);
  }

  /// `TipoPrenda.id` que `GarmentCategoryLayer.layer` (en `models/garment.dart`)
  /// clasifica como capa exterior por su [GarmentCategory] (chaqueta), pero
  /// que por función real de capa son intermedia/abrigo ligero — ver el
  /// comentario de la clase. `GarmentCategoryLayer.layer` no puede distinguir
  /// esto porque agrupa las 25 `TipoPrenda` en solo 6 `GarmentCategory`;
  /// [_layerOf] afina por `tipoPrendaId` sobre esa base, mismo patrón que ya
  /// usa [_sportIncompatibleTipoPrendaIds] para el filtro de deporte.
  static const _midTipoPrendaIds = {'chaleco'};

  /// Capa formal de [garment] para este motor: por defecto la de
  /// `GarmentCategoryLayer.layer` (según su [GarmentCategory]), salvo que su
  /// `tipoPrendaId` esté en [_midTipoPrendaIds], en cuyo caso se reclasifica
  /// a [GarmentLayer.mid]. Una prenda sin `tipoPrendaId` (o con uno no
  /// reconocido) usa la capa de su categoría sin más — no hay dato granular
  /// del que fiarse, mismo criterio conservador que el resto del motor.
  static GarmentLayer? _layerOf(Garment garment) {
    if (garment.tipoPrendaId != null && _midTipoPrendaIds.contains(garment.tipoPrendaId)) {
      return GarmentLayer.mid;
    }
    return garment.category.layer;
  }

  /// ## Garantía de resultado
  ///
  /// Mientras el armario (o el subconjunto que se le pase) tenga AL MENOS una
  /// parte superior (camiseta o chaqueta), un pantalón y un calzado, este
  /// método SIEMPRE devuelve un outfit completo, por muy restrictivos que sean
  /// la ocasión, el clima o la compatibilidad entre prendas: primero intenta
  /// las combinaciones que cumplen todos los filtros duros y, si no hay
  /// ninguna, cae al fallback por proximidad (ver [_scoreProximity] y el
  /// comentario junto a `if (candidates.isEmpty && !locked)` en el cuerpo),
  /// que puntúa TODAS las combinaciones por cercanía y elige la más parecida.
  /// Solo lanza [Exception] cuando falta un hueco estructural entero (sin
  /// ninguna prenda superior, o sin pantalón, o sin calzado) o cuando
  /// [lockedMatch] no lo cumple ninguna prenda.
  ///
  /// [lockedMatch] fija una prenda o categoría elegida explícitamente por el
  /// usuario (p. ej. `DailyOutfitCategoryOption.matches`, o un predicado por
  /// `id` para una prenda concreta): si al menos una prenda del armario lo
  /// cumple, el outfit generado la incluye SIEMPRE, saltándose todos los
  /// filtros duros de compatibilidad (deporte, layering, color/estilo/
  /// temporada) que normalmente podrían excluirla o bloquear la generación.
  /// Las prendas complementarias se eligen puntuando cada combinación
  /// candidata (ver [_scoreLocked]) en vez de filtrarlas, así que ninguna
  /// incompatibilidad entre ellas puede hacer fallar la generación mientras
  /// el armario tenga al menos una prenda por hueco estructural (parte
  /// superior, pantalón, calzado). Si ninguna prenda del armario cumple
  /// [lockedMatch], lanza [Exception] en vez de ignorar la petición en
  /// silencio.
  ///
  /// [currentTemp] es la temperatura actual en °C, usada únicamente dentro
  /// de [_scoreLocked] (junto con el rango `TipoPrenda.tempMin`/`tempMax` de
  /// cada prenda) para puntuar qué tan bien encaja cada complemento con el
  /// tiempo de hoy. No afecta al modo sin `lockedMatch`: ahí el clima solo
  /// entra vía [weather] (ver [_targetSeason]), igual que hoy.
  ///
  /// [selectedAccessories] es la selección múltiple e independiente de
  /// [AccessoryType] del usuario (ver la sección "Accesorios" de
  /// `daily_outfit_screen.dart`) — completamente aparte de [lockedMatch], que
  /// solo fija una prenda/categoría PRINCIPAL (parte superior, pantalón o
  /// calzado; ver [_lockRestrict]). Con [selectedAccessories] no nulo,
  /// [_pickAccessories] sustituye por completo su selección automática de
  /// hasta [_maxAccessories] complementos "adivinados" por color/estilo por
  /// esta otra: para cada tipo de la lista, busca la mejor opción disponible
  /// en el armario (ver [_accessoryScore]) e la incluye, sin límite de
  /// cantidad ni filtro de color — si algún tipo no tiene ninguna prenda en
  /// el armario, se omite ese tipo en silencio, nunca bloquea la generación.
  /// `null` (el valor por defecto) preserva el comportamiento de siempre.
  ///
  /// Los cinco parámetros siguientes atacan la repetición de prendas del
  /// "Outfit del día" (ver `daily_outfit_screen.dart`). Todos tienen un valor
  /// por defecto que reproduce EXACTAMENTE el comportamiento anterior, así que
  /// cualquier llamada que no los pase (tests incluidos) se comporta igual que
  /// antes:
  ///
  ///  - [excludeGarmentIds]: exclusión DURA. Las prendas con estos ids se
  ///    quitan de sus buckets antes de combinar (rotación obligatoria de la
  ///    parte superior). Nunca vacía un hueco estructural: si al quitarlas un
  ///    bucket quedaría vacío, se restaura entero. La prenda fijada por
  ///    [lockedMatch] jamás se excluye aunque esté en esta lista.
  ///  - [recentGarmentIds]: pool de "cooldown" (prendas vistas en las últimas
  ///    sugerencias). Penalización SUAVE de puntuación (-1 normal / -2 si es
  ///    capa base), nunca un filtro.
  ///  - [previousOutfitIds]: prendas del outfit que el usuario tiene ahora
  ///    mismo en pantalla. Penalización más fuerte (-2 / -4 capa base) para
  ///    empujar a un cambio visible sin hacerlas inalcanzables.
  ///  - [strictTops]: pre-filtro más estricto SOLO del bucket de capa base
  ///    (camisetas/tops). Descarta los que no encajan en estilo de ocasión,
  ///    temporada del clima o rango de temperatura (sin la exención de
  ///    `tipoPrendaId` nulo que sí aplica `filterGarmentsByTemperature`). Si
  ///    deja el bucket vacío, `generate` lanza y la cascada de la pantalla cae
  ///    al siguiente intento no estricto — ese es el fallback controlado.
  ///  - [random]: `null` (por defecto) mantiene la selección 100% determinista
  ///    de siempre. Con un [Random], la sugerencia principal se elige por
  ///    sorteo ponderado entre los mejores candidatos (ver [_selectVaried]),
  ///    para que un armario pequeño no devuelva siempre el mismo outfit.
  ///
  /// [l10n] localiza el texto de `explanation` de cada [OutfitRecommendation]
  /// al idioma activo. `null` (por defecto, y en las llamadas sin `BuildContext`
  /// como `calendar_screen.dart` o los tests) mantiene la redacción en español.
  static List<OutfitRecommendation> generate(
    List<Garment> garments, {
    OutfitOccasion? occasion,
    WeatherCondition? weather,
    int count = 3,
    bool Function(Garment garment)? lockedMatch,
    double? currentTemp,
    List<AccessoryType>? selectedAccessories,
    Set<String> excludeGarmentIds = const {},
    Set<String> recentGarmentIds = const {},
    Set<String> previousOutfitIds = const {},
    bool strictTops = false,
    Random? random,
    AppLocalizations? l10n,
  }) {
    final locked = lockedMatch != null;
    if (locked && !garments.any(lockedMatch)) {
      throw Exception('Ninguna prenda del armario coincide con la prenda o categoría fijada.');
    }

    final eligibleGarments = occasion == OutfitOccasion.deporte
        ? garments.where((g) => _isSportCompatible(g) || (locked && lockedMatch(g))).toList()
        : garments;

    final targetStyle = _targetStyle(occasion);
    final targetSeason = _targetSeason(weather);

    // Rotación obligatoria: la prenda fijada por el usuario nunca se excluye
    // (se pidió a propósito), así que se resta de la lista de exclusión antes
    // de aplicarla. `_dropExcluded` nunca deja un bucket vacío: si al quitar
    // las excluidas se quedaría sin nada, devuelve el bucket entero — mejor
    // repetir un top que no poder generar outfit.
    final lockedIds = locked
        ? eligibleGarments.where(lockedMatch).map((g) => g.id).toSet()
        : const <String>{};
    final effectiveExclude = excludeGarmentIds.difference(lockedIds);
    List<Garment> dropExcluded(List<Garment> bucket) {
      if (effectiveExclude.isEmpty) return bucket;
      final kept = bucket.where((g) => !effectiveExclude.contains(g.id)).toList();
      return kept.isEmpty ? bucket : kept;
    }

    final rawMidLayers = eligibleGarments.where((g) => _layerOf(g) == GarmentLayer.mid).toList();

    var strictBaseTops =
        dropExcluded(eligibleGarments.where((g) => _layerOf(g) == GarmentLayer.base).toList());
    if (strictTops) {
      strictBaseTops = strictBaseTops
          .where((t) => _topPassesStrict(t, targetStyle, targetSeason, currentTemp))
          .toList();
      // Deliberadamente NO se restaura si queda vacío: bucket base vacío ->
      // upperCombos vacío -> este `generate` lanza -> la cascada de
      // `daily_outfit_screen.dart` cae al siguiente intento (no estricto).
    }
    final baseTops = _lockRestrict(strictBaseTops, lockedMatch);
    final midLayers = _lockRestrict(dropExcluded(rawMidLayers), lockedMatch);
    final outerLayers = _lockRestrict(
      dropExcluded(eligibleGarments.where((g) => _layerOf(g) == GarmentLayer.outer).toList()),
      lockedMatch,
    );
    final bottoms = _lockRestrict(
      dropExcluded(eligibleGarments.where((g) => g.category == GarmentCategory.pantalon).toList()),
      lockedMatch,
    );
    final shoes = _lockRestrict(
      dropExcluded(eligibleGarments.where((g) => g.category == GarmentCategory.calzado).toList()),
      lockedMatch,
    );
    final accessories =
        eligibleGarments.where((g) => g.category == GarmentCategory.complemento).toList();

    final midIsLockedHueco = locked && rawMidLayers.any(lockedMatch);

    final upperCombos = _buildUpperCombos(
      baseTops,
      midLayers,
      outerLayers,
      relaxCompatibility: locked,
      allowMidAlone: midIsLockedHueco,
    );

    if (upperCombos.isEmpty || bottoms.isEmpty || shoes.isEmpty) {
      throw Exception(
        'Añade al menos una prenda superior, un pantalón y un calzado para generar outfits.',
      );
    }

    final candidates = <_ScoredCombo>[];
    for (final upper in upperCombos) {
      for (final bottom in bottoms) {
        if (!locked && !_groupCompatibleWith(upper, bottom)) continue;
        for (final shoe in shoes) {
          if (!locked && !_groupCompatibleWith(upper, shoe)) continue;
          if (!locked && !_piecesCompatible(bottom, shoe)) continue;
          final pieces = [...upper, bottom, shoe];
          candidates.add(
            locked
                ? _scoreLocked(pieces, lockedMatch, targetStyle, targetSeason, currentTemp,
                    recentGarmentIds, previousOutfitIds)
                : _score(pieces, targetStyle, targetSeason, recentGarmentIds, previousOutfitIds),
          );
        }
      }
    }

    // Fallback por proximidad: en modo normal, si NINGUNA combinación pasó los
    // filtros duros de compatibilidad entre piezas (color/estilo/temporada),
    // no se devuelve vacío ni se lanza: se puntúan TODAS las combinaciones
    // posibles por CERCANÍA a los criterios (ver [_scoreProximity]) y se elige
    // la mejor. Así un armario con prendas que "chocan" entre sí, o unos
    // filtros de clima/ocasión muy restrictivos, siempre dan un outfit
    // completo con la ropa más parecida a lo pedido, en vez de un hueco vacío.
    // Se reconstruyen además las combos de parte superior sin el filtro de
    // compatibilidad de capas (`relaxCompatibility: true`) para no perder las
    // opciones en capas por el camino. En modo locked el triple bucle de
    // arriba ya no filtra, así que este fallback no aplica: allí `candidates`
    // solo puede quedar vacío por falta de un hueco estructural, ya descartado.
    if (candidates.isEmpty && !locked) {
      final relaxedUpperCombos = _buildUpperCombos(
        baseTops,
        midLayers,
        outerLayers,
        relaxCompatibility: true,
      );
      for (final upper in relaxedUpperCombos) {
        for (final bottom in bottoms) {
          for (final shoe in shoes) {
            candidates.add(
              _scoreProximity([...upper, bottom, shoe], targetStyle, targetSeason,
                  currentTemp, recentGarmentIds, previousOutfitIds),
            );
          }
        }
      }
    }

    // Solo alcanzable si falta un hueco estructural (sin parte superior,
    // pantalón o calzado); la restrictividad de los filtros nunca llega aquí.
    if (candidates.isEmpty) {
      throw Exception('No hay suficientes prendas compatibles entre sí para armar un outfit.');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    final selected = _selectVaried(candidates, count, random);

    return List.generate(
      selected.length,
      (i) => _toRecommendation(
        selected[i],
        i,
        occasion,
        accessories,
        targetStyle,
        targetSeason,
        lockedMatch: lockedMatch,
        selectedAccessories: selectedAccessories,
        l10n: l10n,
      ),
    );
  }

  /// Si [lockedMatch] encuentra coincidencias dentro de [bucket], ESE bucket
  /// es el hueco fijado por el usuario: se restringe a solo esas
  /// coincidencias para que toda combinación construida a partir de él
  /// incluya siempre la prenda fijada. Sin coincidencias en este bucket
  /// concreto, no es su hueco: se devuelve sin tocar.
  static List<Garment> _lockRestrict(
    List<Garment> bucket,
    bool Function(Garment garment)? lockedMatch,
  ) {
    if (lockedMatch == null) return bucket;
    final locked = bucket.where(lockedMatch).toList();
    return locked.isEmpty ? bucket : locked;
  }

  /// Las combinaciones válidas de capas superiores del sistema de capas
  /// formal (ver el comentario de la clase): capa base sola (Opción A), base
  /// + intermedia sin exterior (Opción B), base + exterior sin intermedia
  /// (Opción C), las tres capas juntas, y exterior sola (preexistente, se
  /// mantiene por compatibilidad). Cada combinación se valida por
  /// compatibilidad (color/estilo/temporada) entre TODOS sus pares antes de
  /// entrar en la lista. [relaxCompatibility] desactiva esas comprobaciones
  /// de [_piecesCompatible] (usado en modo `lockedMatch`, ver [generate]):
  /// con el valor por defecto `false` este método reproduce exactamente las
  /// mismas comprobaciones de siempre, solo con más formas de combo
  /// disponibles (ver `Sistema de capas` en el comentario de la clase).
  /// [allowMidAlone] añade la capa intermedia sola, sin ninguna base
  /// disponible, como combo adicional — bypass válido solo cuando esa capa
  /// intermedia ES el hueco fijado por el usuario (ver `midIsLockedHueco` en
  /// [generate]) y no hay ninguna base con la que emparejarla.
  static List<List<Garment>> _buildUpperCombos(
    List<Garment> baseTops,
    List<Garment> midLayers,
    List<Garment> outerLayers, {
    bool relaxCompatibility = false,
    bool allowMidAlone = false,
  }) {
    final combos = <List<Garment>>[
      for (final base in baseTops) [base],
      for (final outer in outerLayers) [outer],
    ];

    for (final base in baseTops) {
      // Opción B: base + intermedia, sin exterior (p. ej. camiseta + jersey).
      for (final mid in midLayers) {
        if (!relaxCompatibility && !_piecesCompatible(base, mid)) continue;
        combos.add([base, mid]);

        // Las tres capas a la vez (p. ej. camiseta + sudadera + chaqueta).
        for (final outer in outerLayers) {
          if (!relaxCompatibility && !_piecesCompatible(base, outer)) continue;
          if (!relaxCompatibility && !_piecesCompatible(mid, outer)) continue;
          combos.add([base, mid, outer]);
        }
      }

      // Opción C: base + exterior, sin intermedia (p. ej. camisa + chaqueta).
      for (final outer in outerLayers) {
        if (!relaxCompatibility && !_piecesCompatible(base, outer)) continue;
        combos.add([base, outer]);
      }
    }

    if (allowMidAlone) {
      for (final mid in midLayers) {
        combos.add([mid]);
      }
    }

    return combos;
  }

  /// Todas las prendas de [group] son compatibles individualmente con
  /// [other] (mismo criterio que [_piecesCompatible] par a par).
  static bool _groupCompatibleWith(List<Garment> group, Garment other) =>
      group.every((piece) => _piecesCompatible(piece, other));

  static bool _piecesCompatible(Garment a, Garment b) =>
      _colorsCompatible(a, b) &&
      _stylesCompatible(a.style, b.style) &&
      _seasonsCompatible(a.season, b.season);

  /// Dos prendas combinan en color si alguna es neutra, si comparten family
  /// (monocromático) o si su par de families está en
  /// [_classicColorFamilyPairs]. Un color que no está en la paleta (prenda
  /// antigua con un nombre ya retirado) no bloquea la combinación.
  static bool _colorsCompatible(Garment a, Garment b) {
    if (GarmentPalette.isNeutral(a.color) || GarmentPalette.isNeutral(b.color)) return true;
    final familyA = GarmentPalette.entryFor(a.color)?.family;
    final familyB = GarmentPalette.entryFor(b.color)?.family;
    if (familyA == null || familyB == null) return true;
    if (familyA == familyB) return true;
    return _classicColorFamilyPairs.contains((familyA, familyB)) ||
        _classicColorFamilyPairs.contains((familyB, familyA));
  }

  static bool _stylesCompatible(GarmentStyle a, GarmentStyle b) {
    if (a == b) return true;
    return _compatibleStyles[a]?.contains(b) ?? false;
  }

  static bool _seasonsCompatible(GarmentSeason a, GarmentSeason b) {
    if (a == b) return true;
    return a == GarmentSeason.todoElAno || b == GarmentSeason.todoElAno;
  }

  static GarmentStyle? _targetStyle(OutfitOccasion? occasion) {
    switch (occasion) {
      case OutfitOccasion.trabajo:
        return GarmentStyle.trabajo;
      case OutfitOccasion.casual:
        return GarmentStyle.casual;
      case OutfitOccasion.fiesta:
        return GarmentStyle.elegante;
      case OutfitOccasion.deporte:
        return GarmentStyle.deportivo;
      case null:
        return null;
    }
  }

  /// `lluvia` no tiene una temporada asociada: el modelo no guarda si una
  /// prenda es impermeable, así que ese chip solo se refleja en el texto de
  /// la sugerencia, nunca como filtro/bonus de temporada.
  static GarmentSeason? _targetSeason(WeatherCondition? weather) {
    switch (weather) {
      case WeatherCondition.calor:
        return GarmentSeason.verano;
      case WeatherCondition.frio:
        return GarmentSeason.invierno;
      case WeatherCondition.lluvia:
      case null:
        return null;
    }
  }

  static _ScoredCombo _score(
    List<Garment> pieces,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason,
    Set<String> recentIds,
    Set<String> previousIds,
  ) {
    final allNeutral = pieces.every((g) => GarmentPalette.isNeutral(g.color));
    final sameStyle = pieces.every((g) => g.style == pieces.first.style);
    final styleContextMatched = targetStyle != null && pieces.any((g) => g.style == targetStyle);
    final seasonContextMatched =
        targetSeason != null && pieces.any((g) => g.season == targetSeason);

    var score = 0;
    if (styleContextMatched) score += 2;
    if (seasonContextMatched) score += 1;
    if (allNeutral) score += 1;
    if (sameStyle) score += 1;
    score -= _repeatPenalty(pieces, recentIds, previousIds);

    return _ScoredCombo(
      pieces: pieces,
      score: score,
      allNeutral: allNeutral,
      sameStyle: sameStyle,
      seasonContextMatched: seasonContextMatched,
    );
  }

  /// Puntuación usada SOLO en modo `lockedMatch` (ver [generate]), en vez de
  /// [_score]: reemplaza los filtros duros de compatibilidad por señales
  /// aditivas, priorizadas en el orden que pide la maximización del resto
  /// del look: a) afinidad cromática con la prenda fijada (peso +3/+1), b)
  /// adecuación a [currentTemp] vía `TipoPrenda.tempMin`/`tempMax` (peso
  /// +2/+1), c) coherencia de estilo/temporada de contexto (peso +1 cada
  /// una, igual que [_score]). Se usan variantes "todo/algo" porque el
  /// número de piezas libres varía entre combos (1 a 4): contar en bruto por
  /// pieza sesgaría a favor de los combos con más piezas.
  ///
  /// Además, +1 si la prenda fijada es de capa intermedia ([GarmentLayer.mid])
  /// y el combo incluye una capa base: sin este bonus, "jersey + camiseta" y
  /// "jersey solo" pueden empatar en las demás señales (p. ej. armario con
  /// colores neutros, sin `currentTemp`) y el desempate quedaría en manos del
  /// orden de construcción de [_buildUpperCombos], nada explícito ni fiable.
  /// Con el bonus, el motor prioriza determinísticamente buscarle una base a
  /// la capa intermedia fijada — tal como se le pediría a una persona real
  /// vistiendo a partir de "quiero llevar este jersey" — y solo se queda sin
  /// ella cuando ninguna base disponible puntúa mejor en color/temperatura.
  static _ScoredCombo _scoreLocked(
    List<Garment> pieces,
    bool Function(Garment garment) lockedMatch,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason,
    double? currentTemp,
    Set<String> recentIds,
    Set<String> previousIds,
  ) {
    final lockedPieces = pieces.where(lockedMatch).toList();
    final freePieces = pieces.where((p) => !lockedMatch(p)).toList();

    bool colorOk(Garment free) =>
        lockedPieces.every((lockedPiece) => _colorsCompatible(free, lockedPiece));
    final colorMatches = freePieces.where(colorOk).length;
    final colorAffinityAll = freePieces.isNotEmpty && colorMatches == freePieces.length;
    final colorAffinityAny = !colorAffinityAll && colorMatches > 0;

    var tempAffinityAll = false;
    var tempAffinityAny = false;
    if (currentTemp != null) {
      final fits = <bool>[];
      for (final free in freePieces) {
        final tipo = _tipoPrendaOf(free);
        if (tipo == null) continue;
        fits.add(currentTemp >= tipo.tempMin && currentTemp <= tipo.tempMax);
      }
      if (fits.isNotEmpty) {
        final fitCount = fits.where((ok) => ok).length;
        tempAffinityAll = fitCount == fits.length;
        tempAffinityAny = !tempAffinityAll && fitCount > 0;
      }
    }

    final allNeutral = pieces.every((g) => GarmentPalette.isNeutral(g.color));
    final sameStyle = pieces.every((g) => g.style == pieces.first.style);
    final styleContextMatched = targetStyle != null && pieces.any((g) => g.style == targetStyle);
    final seasonContextMatched =
        targetSeason != null && pieces.any((g) => g.season == targetSeason);
    final lockedMidHasBase = lockedPieces.any((p) => _layerOf(p) == GarmentLayer.mid) &&
        pieces.any((p) => _layerOf(p) == GarmentLayer.base);

    var score = 0;
    if (colorAffinityAll) score += 3;
    if (colorAffinityAny) score += 1;
    if (tempAffinityAll) score += 2;
    if (tempAffinityAny) score += 1;
    if (styleContextMatched) score += 1;
    if (seasonContextMatched) score += 1;
    if (allNeutral) score += 1;
    if (sameStyle) score += 1;
    if (lockedMidHasBase) score += 1;
    // La prenda fijada nunca penaliza (el usuario la pidió); el resto del look
    // sí, para que un cambio de parámetro varíe los acompañantes.
    score -= _repeatPenalty(pieces, recentIds, previousIds, lockedMatch: lockedMatch);

    return _ScoredCombo(
      pieces: pieces,
      score: score,
      allNeutral: allNeutral,
      sameStyle: sameStyle,
      seasonContextMatched: seasonContextMatched,
    );
  }

  /// Puntuación del FALLBACK POR PROXIMIDAD (ver [generate]): se usa cuando
  /// ningún combo pasó los filtros duros de compatibilidad y hay que elegir
  /// "el menos malo" en vez de no devolver nada. Todo suma o resta (nunca
  /// filtra), de forma que el mejor combo es el más parecido a los criterios:
  ///
  ///  - Armonía interna: por cada par de piezas, +1 si combinan en color, +1
  ///    en estilo y +1 en temporada (mismo criterio que [_piecesCompatible],
  ///    pero como preferencia graduable en vez de todo-o-nada).
  ///  - Cercanía al estilo de la ocasión: +3 por pieza que ES de [targetStyle],
  ///    +1 por pieza de un estilo compatible con él.
  ///  - Cercanía a la temporada: +1 por pieza de [targetSeason] o de uso todo
  ///    el año.
  ///  - Cercanía a la temperatura: +2 por pieza dentro de su rango para
  ///    [currentTemp]; si está fuera, resta según lo lejos que quede del rango
  ///    (1 punto por cada 5 °C), para preferir la prenda menos inadecuada.
  ///  - Menos la penalización de cooldown ([_repeatPenalty]).
  ///
  /// El combo resultante se marca como aproximado ([_ScoredCombo.approximate])
  /// para que la explicación del outfit sea honesta sobre que es la opción más
  /// cercana disponible, no una combinación perfecta.
  static _ScoredCombo _scoreProximity(
    List<Garment> pieces,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason,
    double? currentTemp,
    Set<String> recentIds,
    Set<String> previousIds,
  ) {
    final allNeutral = pieces.every((g) => GarmentPalette.isNeutral(g.color));
    final sameStyle = pieces.every((g) => g.style == pieces.first.style);
    final seasonContextMatched =
        targetSeason != null && pieces.any((g) => g.season == targetSeason);

    var score = 0;

    for (var i = 0; i < pieces.length; i++) {
      for (var j = i + 1; j < pieces.length; j++) {
        if (_colorsCompatible(pieces[i], pieces[j])) score += 1;
        if (_stylesCompatible(pieces[i].style, pieces[j].style)) score += 1;
        if (_seasonsCompatible(pieces[i].season, pieces[j].season)) score += 1;
      }
    }

    if (targetStyle != null) {
      for (final g in pieces) {
        if (g.style == targetStyle) {
          score += 3;
        } else if (_stylesCompatible(g.style, targetStyle)) {
          score += 1;
        }
      }
    }

    if (targetSeason != null) {
      for (final g in pieces) {
        if (g.season == targetSeason || g.season == GarmentSeason.todoElAno) score += 1;
      }
    }

    if (currentTemp != null) {
      for (final g in pieces) {
        final tipo = _tipoPrendaOf(g);
        if (tipo == null) continue;
        if (currentTemp >= tipo.tempMin && currentTemp <= tipo.tempMax) {
          score += 2;
        } else {
          final distance = currentTemp < tipo.tempMin
              ? tipo.tempMin - currentTemp
              : currentTemp - tipo.tempMax;
          score -= (distance / 5).ceil();
        }
      }
    }

    score -= _repeatPenalty(pieces, recentIds, previousIds);

    return _ScoredCombo(
      pieces: pieces,
      score: score,
      allNeutral: allNeutral,
      sameStyle: sameStyle,
      seasonContextMatched: seasonContextMatched,
      approximate: true,
    );
  }

  /// Penalización de "cooldown": resta puntos a un combo por cada prenda suya
  /// vista hace poco. [previousIds] (outfit ahora en pantalla) pesa más que
  /// [recentIds] (pool de las últimas sugerencias); la capa base pesa más que
  /// las demás porque la repetición de camiseta/top es la queja principal. La
  /// prenda fijada por [lockedMatch] queda exenta. Nunca es un filtro: el peor
  /// caso es que un combo caiga a puntuación negativa, y `sort` +
  /// [_selectVaried] lo toleran (todo es relativo, sin umbrales absolutos).
  static int _repeatPenalty(
    List<Garment> pieces,
    Set<String> recentIds,
    Set<String> previousIds, {
    bool Function(Garment garment)? lockedMatch,
  }) {
    if (recentIds.isEmpty && previousIds.isEmpty) return 0;
    var penalty = 0;
    for (final g in pieces) {
      if (lockedMatch != null && lockedMatch(g)) continue;
      final isBase = _layerOf(g) == GarmentLayer.base;
      if (previousIds.contains(g.id)) {
        penalty += isBase ? 4 : 2;
      } else if (recentIds.contains(g.id)) {
        penalty += isBase ? 2 : 1;
      }
    }
    return penalty;
  }

  /// Filtro estricto de una prenda de capa base para `strictTops` (ver
  /// [generate]): descarta la que no encaja con el estilo de la ocasión, la
  /// temporada del clima o el rango de temperatura de su `tipoPrenda`. A
  /// diferencia de `OutfitRecommendationService.filterGarmentsByTemperature`,
  /// aquí una prenda SIN `tipoPrendaId` (o con uno desconocido) NO pasa cuando
  /// hay `currentTemp`: en modo estricto se prefiere exigir el dato a arriesgar
  /// un top inadecuado, porque siempre hay un intento no estricto detrás en la
  /// cascada.
  static bool _topPassesStrict(
    Garment top,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason,
    double? currentTemp,
  ) {
    if (targetStyle != null && !_stylesCompatible(top.style, targetStyle)) return false;
    if (targetSeason != null && !_seasonsCompatible(top.season, targetSeason)) return false;
    if (currentTemp != null) {
      final tipo = _tipoPrendaOf(top);
      if (tipo == null) return false;
      if (currentTemp < tipo.tempMin || currentTemp > tipo.tempMax) return false;
    }
    return true;
  }

  /// Misma búsqueda que `OutfitRecommendationService._tipoPrendaOf`,
  /// duplicada aquí porque los miembros privados no se comparten entre
  /// archivos en Dart. Único punto de lectura del rango de temperatura para
  /// el scoring de temperatura de [_scoreLocked].
  static TipoPrenda? _tipoPrendaOf(Garment garment) {
    final id = garment.tipoPrendaId;
    if (id == null) return null;
    for (final tipo in tiposDePrenda) {
      if (tipo.id == id) return tipo;
    }
    return null;
  }

  /// Recorre los combos ya ordenados por puntuación y descarta los que
  /// comparten 2 o más prendas con uno ya elegido, para que las [count]
  /// sugerencias no repitan casi siempre las mismas piezas. Si el armario es
  /// pequeño y no alcanza para evitar solapes, rellena con los mejores
  /// candidatos descartados en esa primera pasada.
  ///
  /// Con [random] `null` (por defecto en todas las llamadas salvo la de la
  /// pantalla) ejecuta EXACTAMENTE el algoritmo determinista de siempre: cada
  /// test existente obtiene el mismo resultado byte a byte. Con un [Random],
  /// en cada hueco sortea entre los candidatos casi-óptimos (misma puntuación
  /// ±1 respecto al mejor disponible, hasta 5) con pesos por rango — así un
  /// armario pequeño deja de devolver siempre el mismo outfit sin bajar la
  /// calidad (solo entran combos a un punto del mejor).
  static List<_ScoredCombo> _selectVaried(
    List<_ScoredCombo> sorted,
    int count, [
    Random? random,
  ]) {
    if (random == null) {
      final selected = <_ScoredCombo>[];
      final skipped = <_ScoredCombo>[];

      for (final combo in sorted) {
        if (selected.length >= count) break;
        final overlapsTooMuch =
            selected.any((s) => s.ids.intersection(combo.ids).length >= 2);
        if (overlapsTooMuch) {
          skipped.add(combo);
        } else {
          selected.add(combo);
        }
      }

      for (final combo in skipped) {
        if (selected.length >= count) break;
        selected.add(combo);
      }

      return selected;
    }

    final selected = <_ScoredCombo>[];
    final remaining = [...sorted]; // preserva el orden por puntuación descendente
    while (selected.length < count && remaining.isNotEmpty) {
      final eligible = remaining
          .where((c) => selected.every((s) => s.ids.intersection(c.ids).length < 2))
          .toList();
      final pool = eligible.isNotEmpty ? eligible : remaining;
      final bestScore = pool.first.score;
      final window = pool.where((c) => c.score >= bestScore - 1).take(5).toList();
      final pick = _weightedPick(window, random);
      selected.add(pick);
      remaining.remove(pick);
    }
    return selected;
  }

  /// Elige un elemento de [window] (ya ordenada por puntuación descendente) con
  /// pesos por RANGO, no proporcionales a la puntuación: `window[0]` pesa `n`,
  /// `window[1]` pesa `n-1`, ... el último pesa `1`. P(mejor) = `2/(n+1)`
  /// (33% con 5 candidatos, 50% con 3). Los pesos por rango evitan que un
  /// único combo con puntuación ligeramente superior acapare el sorteo, algo
  /// probable con puntuaciones que son enteros diminutos y con empates
  /// frecuentes (un softmax degeneraría a uniforme). [window] nunca está
  /// vacía (siempre hay al menos el mejor candidato del pool).
  static _ScoredCombo _weightedPick(List<_ScoredCombo> window, Random random) {
    final n = window.length;
    if (n == 1) return window.first;
    var r = random.nextInt(n * (n + 1) ~/ 2);
    for (var i = 0; i < n; i++) {
      final weight = n - i;
      if (r < weight) return window[i];
      r -= weight;
    }
    return window.last;
  }

  static OutfitRecommendation _toRecommendation(
    _ScoredCombo combo,
    int index,
    OutfitOccasion? occasion,
    List<Garment> availableAccessories,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason, {
    bool Function(Garment garment)? lockedMatch,
    List<AccessoryType>? selectedAccessories,
    AppLocalizations? l10n,
  }) {
    final dominantStyle = _dominantStyle(combo.pieces);
    final template = _titleTemplates[index % _titleTemplates.length];
    final styleForTitle =
        dominantStyle == GarmentStyle.trabajo ? 'de Trabajo' : dominantStyle.label;
    final title = '$template $styleForTitle';

    final occasionText = occasion?.label ?? dominantStyle.label;

    final accessories = _pickAccessories(
      availableAccessories,
      combo.pieces,
      targetStyle,
      targetSeason,
      lockedMatch: lockedMatch,
      selectedAccessories: selectedAccessories,
    );

    final families =
        combo.pieces.map((g) => GarmentPalette.entryFor(g.color)?.family).toSet();

    // Combo del fallback por proximidad: ninguna combinación cumplía todos los
    // filtros, así que la redacción deja claro que es la más parecida
    // disponible en vez de vender una coherencia que no tiene (ver
    // `combo.approximate` en las dos funciones de redacción).
    final explanation = l10n != null
        ? _localizedExplanation(l10n, combo, dominantStyle, families, accessories)
        : _spanishExplanation(combo, dominantStyle, families, accessories);

    return OutfitRecommendation(
      title: title,
      occasion: occasionText,
      explanation: explanation,
      garments: [...combo.pieces, ...accessories],
    );
  }

  /// Redacta `explanation` en español — comportamiento por defecto cuando
  /// [generate] se llama sin `l10n` (`calendar_screen.dart`, tests).
  static String _spanishExplanation(
    _ScoredCombo combo,
    GarmentStyle dominantStyle,
    Set<String?> families,
    List<Garment> accessories,
  ) {
    final reasons = <String>[];
    if (combo.allNeutral) {
      reasons.add('combina tonos neutros que van bien entre sí');
    } else if (families.length == 1) {
      reasons.add('mantiene una paleta monocromática');
    } else if (!combo.approximate) {
      reasons.add('mezcla colores que combinan clásicamente');
    }
    if (combo.sameStyle) {
      reasons.add('con un estilo ${dominantStyle.label.toLowerCase()} coherente');
    }
    if (combo.seasonContextMatched) {
      reasons.add('pensado para la temporada indicada');
    }
    if (accessories.isNotEmpty) {
      reasons.add('con ${accessories.map((a) => a.color.toLowerCase()).join(' y ')} '
          '${accessories.length == 1 ? 'de complemento' : 'en los complementos'}');
    }
    return combo.approximate
        ? (reasons.isEmpty
            ? 'Es la combinación más parecida a lo que buscas con tu armario de hoy.'
            : 'Es la combinación más parecida a lo que buscas: ${reasons.join(', ')}.')
        : 'Este outfit ${reasons.join(', ')}.';
  }

  /// Igual que [_spanishExplanation] pero tomando cada fragmento del
  /// diccionario [AppLocalizations] del idioma activo. Los nombres de color de
  /// los accesorios (dato del armario, siempre en español) se omiten aquí a
  /// propósito para no dejar palabras sueltas sin traducir en la frase.
  static String _localizedExplanation(
    AppLocalizations l10n,
    _ScoredCombo combo,
    GarmentStyle dominantStyle,
    Set<String?> families,
    List<Garment> accessories,
  ) {
    final reasons = <String>[];
    if (combo.allNeutral) {
      reasons.add(l10n.t('outfit_reason_all_neutral'));
    } else if (families.length == 1) {
      reasons.add(l10n.t('outfit_reason_monochrome'));
    } else if (!combo.approximate) {
      reasons.add(l10n.t('outfit_reason_classic_colors'));
    }
    if (combo.sameStyle) {
      reasons.add(l10n.t(
        'outfit_reason_same_style',
        {'style': l10n.style(dominantStyle).toLowerCase()},
      ));
    }
    if (combo.seasonContextMatched) {
      reasons.add(l10n.t('outfit_reason_season'));
    }
    if (accessories.isNotEmpty) {
      reasons.add(l10n.t('outfit_reason_accessories'));
    }
    final joined = reasons.join(l10n.t('outfit_expl_sep'));
    return combo.approximate
        ? (reasons.isEmpty
            ? l10n.t('outfit_expl_approx_empty')
            : l10n.t('outfit_expl_approx_wrap', {'reasons': joined}))
        : l10n.t('outfit_expl_wrap', {'reasons': joined});
  }

  /// Como máximo [_maxAccessories] complementos cuyo color combine con TODAS
  /// las prendas del combo (mismo criterio de [_colorsCompatible] que ya usan
  /// las prendas principales entre sí). Entre los compatibles, prioriza los
  /// que además encajan con el estilo/temporada de contexto y evita repetir
  /// el mismo [AccessoryType] mientras haya alternativa, para que la
  /// selección se note variada (p.ej. no elegir dos gorras a la vez).
  static const _maxAccessories = 2;

  /// [selectedAccessories] (selección múltiple e independiente, ver
  /// [generate]) sustituye por completo la selección automática de más
  /// abajo cuando no es `null`: para cada [AccessoryType] de la lista, busca
  /// entre [accessories] las prendas de ese tipo, elige la de mayor
  /// [_accessoryScore] (sin filtrar por color — el usuario la pidió a
  /// propósito, igual que [lockedMatch] con la prenda principal) y la
  /// incluye. Ningún tope de cantidad ([_maxAccessories] no aplica aquí: se
  /// incluyen TODOS los tipos seleccionados que tengan alguna prenda
  /// disponible) y ningún tipo sin prendas bloquea nada, simplemente se
  /// omite. Una lista vacía (el usuario activó la sección pero no marcó
  /// ningún sub-chip) da cero accesorios a propósito, no un fallback al
  /// modo automático.
  ///
  /// [lockedMatch] fuerza la inclusión de un accesorio elegido explícitamente
  /// como prenda PRINCIPAL fija (ver [generate]): entra primero y siempre
  /// (bypass del filtro de color), antes del resto de la lógica normal de
  /// selección. Solo se usa cuando [selectedAccessories] es `null` — en la
  /// práctica no coexisten, ya que `daily_outfit_screen.dart` ya no permite
  /// fijar "Accesorios" como categoría única (ver `DailyOutfitCategoryOption`)
  /// ahora que tiene su propio selector independiente.
  static List<Garment> _pickAccessories(
    List<Garment> accessories,
    List<Garment> comboPieces,
    GarmentStyle? targetStyle,
    GarmentSeason? targetSeason, {
    bool Function(Garment garment)? lockedMatch,
    List<AccessoryType>? selectedAccessories,
  }) {
    if (selectedAccessories != null) {
      final picked = <Garment>[];
      for (final type in selectedAccessories) {
        final ofType = accessories.where((a) => a.accessoryType == type).toList()
          ..sort(
            (a, b) => _accessoryScore(b, targetStyle, targetSeason)
                .compareTo(_accessoryScore(a, targetStyle, targetSeason)),
          );
        if (ofType.isEmpty) continue;
        picked.add(ofType.first);
      }
      return picked;
    }

    bool isLocked(Garment g) => lockedMatch != null && lockedMatch(g);

    final compatible = accessories
        .where(
          (accessory) =>
              isLocked(accessory) ||
              comboPieces.every((piece) => _colorsCompatible(accessory, piece)),
        )
        .toList()
      ..sort(
        (a, b) => _accessoryScore(b, targetStyle, targetSeason)
            .compareTo(_accessoryScore(a, targetStyle, targetSeason)),
      );

    final picked = <Garment>[];
    final usedTypes = <AccessoryType?>{};
    for (final accessory in compatible.where(isLocked)) {
      if (picked.length >= _maxAccessories) break;
      picked.add(accessory);
      usedTypes.add(accessory.accessoryType);
    }
    for (final accessory in compatible) {
      if (picked.length >= _maxAccessories) break;
      if (picked.contains(accessory)) continue;
      if (usedTypes.contains(accessory.accessoryType)) continue;
      picked.add(accessory);
      usedTypes.add(accessory.accessoryType);
    }
    // Si evitar repetir tipo deja huecos libres y aún quedan candidatos
    // compatibles sin usar, se completa con ellos: mejor un tipo repetido
    // que dejar un hueco vacío pudiendo llenarlo.
    if (picked.length < _maxAccessories) {
      for (final accessory in compatible) {
        if (picked.length >= _maxAccessories) break;
        if (picked.contains(accessory)) continue;
        picked.add(accessory);
      }
    }
    return picked;
  }

  static int _accessoryScore(Garment accessory, GarmentStyle? targetStyle, GarmentSeason? targetSeason) {
    var score = 0;
    if (targetStyle != null && accessory.style == targetStyle) score += 2;
    if (targetSeason != null && accessory.season == targetSeason) score += 1;
    if (GarmentPalette.isNeutral(accessory.color)) score += 1;
    return score;
  }

  static GarmentStyle _dominantStyle(List<Garment> pieces) {
    final counts = <GarmentStyle, int>{};
    for (final g in pieces) {
      counts[g.style] = (counts[g.style] ?? 0) + 1;
    }
    var best = pieces.first.style;
    var bestCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }
}

/// Un combo ya validado (parte superior en 1-3 capas + pantalón + calzado),
/// con su puntuación de contexto y las señales que se reutilizan para
/// redactar la explicación del outfit.
class _ScoredCombo {
  final List<Garment> pieces;
  final int score;
  final bool allNeutral;
  final bool sameStyle;
  final bool seasonContextMatched;

  /// `true` si el combo viene del fallback por proximidad ([_scoreProximity]):
  /// es la opción más cercana disponible, no una combinación que cumpla todos
  /// los criterios. Lo usa [_toRecommendation] para matizar la explicación.
  final bool approximate;

  const _ScoredCombo({
    required this.pieces,
    required this.score,
    required this.allNeutral,
    required this.sameStyle,
    required this.seasonContextMatched,
    this.approximate = false,
  });

  Set<String> get ids => pieces.map((g) => g.id).toSet();
}
