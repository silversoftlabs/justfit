import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_enums.dart';
import '../models/garment.dart';
import '../models/outfit_filters.dart';
import '../providers/favorite_outfits_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/location_provider.dart';
import '../providers/outfit_history_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../services/outfit_recommendation_service.dart';
import '../services/weather_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/outfit_flat_lay_view.dart';
import '../widgets/shimmer_box.dart';

/// Mismo mapeo ocasión→estilo que usa `OutfitMatchingService` internamente
/// (`_targetStyle`, privado y solo usado ahí como bonus de puntuación, nunca
/// como filtro duro). Aquí SÍ se usa como filtro: ver [_generateOutfit].
GarmentStyle _styleForOccasion(OutfitOccasion occasion) {
  switch (occasion) {
    case OutfitOccasion.trabajo:
      return GarmentStyle.trabajo;
    case OutfitOccasion.casual:
      return GarmentStyle.casual;
    case OutfitOccasion.fiesta:
      return GarmentStyle.elegante;
    case OutfitOccasion.deporte:
      return GarmentStyle.deportivo;
  }
}

/// Identidad de una recomendación por el conjunto de prendas que la forman,
/// para poder comparar "es la misma combinación de antes" sin importar el
/// orden ni el título/explicación con el que se haya redactado.
Set<String> _garmentIds(OutfitRecommendation recommendation) =>
    recommendation.garments.map((g) => g.id).toSet();

/// Id de la prenda de capa base ("camiseta / parte superior") de una
/// recomendación, o `null` si el outfit es solo de abrigo. Refleja la capa
/// base del motor (`GarmentLayer.base` == `GarmentCategory.camiseta`, que
/// también cubre los vestidos, guardados como camiseta). Se usa para la
/// rotación obligatoria de la parte superior y para registrar el historial.
String? _baseTopId(OutfitRecommendation recommendation) {
  for (final garment in recommendation.garments) {
    if (garment.category == GarmentCategory.camiseta) return garment.id;
  }
  return null;
}

/// Etiquetas automáticas de un outfit al guardarlo en favoritos: los estilos
/// distintos de las prendas que lo forman (sin repetir). La ocasión se guarda
/// aparte, en `FavoriteOutfit.occasion`.
List<String> _autoTags(OutfitRecommendation recommendation) {
  final tags = <String>[];
  for (final garment in recommendation.garments) {
    final label = garment.style.label;
    if (!tags.contains(label)) tags.add(label);
  }
  return tags;
}

/// Categoría fija que el usuario puede pedir para el outfit del día (sección
/// "¿Quieres incluir algo específico?"), más granular que [GarmentCategory]
/// en el caso de "Vestido": el modelo no tiene una categoría propia para
/// prendas de una sola pieza (ver `TipoPrendaMapping.categoria` en
/// `models/tipo_prenda.dart`, que las guarda como
/// [GarmentCategory.camiseta]), así que ese caso se distingue por
/// [Garment.tipoPrendaId] en vez de por categoría.
///
/// Ya NO incluye "Accesorios": los accesorios tienen su propio selector
/// independiente y de selección múltiple (ver [_accessoriesEnabled] /
/// [_selectedAccessoryTypes] en `_DailyOutfitScreenState`), separado a
/// propósito de esta categoría única — antes competían por el mismo campo
/// `_lockedCategory`, así que fijar "Accesorios" desmarcaba cualquier otra
/// prenda principal elegida (y viceversa), cuando ambas cosas deberían poder
/// pedirse a la vez (p. ej. "Sudadera" + "Reloj").
enum DailyOutfitCategoryOption { sudaderaJersey, vaquerosPantalon, vestido, calzado }

extension DailyOutfitCategoryOptionX on DailyOutfitCategoryOption {
  String label(AppLocalizations t) {
    switch (this) {
      case DailyOutfitCategoryOption.sudaderaJersey:
        return t.t('daily_cat_sudadera_jersey');
      case DailyOutfitCategoryOption.vaquerosPantalon:
        return t.t('daily_cat_vaqueros_pantalon');
      case DailyOutfitCategoryOption.vestido:
        return t.t('daily_cat_vestido');
      case DailyOutfitCategoryOption.calzado:
        return t.t('daily_cat_calzado');
    }
  }

  bool matches(Garment g) {
    switch (this) {
      case DailyOutfitCategoryOption.sudaderaJersey:
        return g.category == GarmentCategory.sudadera;
      case DailyOutfitCategoryOption.vaquerosPantalon:
        return g.category == GarmentCategory.pantalon;
      case DailyOutfitCategoryOption.vestido:
        return g.tipoPrendaId == 'vestido';
      case DailyOutfitCategoryOption.calzado:
        return g.category == GarmentCategory.calzado;
    }
  }
}

/// Los seis tipos de complemento que el usuario puede marcar en la sección
/// "Accesorios" de esta pantalla (uno, varios o ninguno a la vez — ver
/// [_DailyOutfitScreenState._selectedAccessoryTypes]), en el orden en que se
/// muestran los sub-chips.
const _dailyOutfitAccessoryTypes = [
  AccessoryType.collar,
  AccessoryType.bolso,
  AccessoryType.reloj,
  AccessoryType.gafas,
  AccessoryType.gorra,
  AccessoryType.pulsera,
];

/// Etiqueta del sub-chip de accesorio: más específica que
/// [AccessoryTypeLabel.label] (que usa una sola palabra, p. ej. "Collar")
/// para que el usuario reconozca variantes habituales del mismo hueco
/// (p. ej. "Collar / Cadena" cubre tanto un collar como una cadena).
String _dailyOutfitAccessoryLabel(AppLocalizations t, AccessoryType type) {
  switch (type) {
    case AccessoryType.collar:
      return t.t('daily_acc_collar');
    case AccessoryType.bolso:
      return t.t('daily_acc_bolso');
    case AccessoryType.reloj:
      return t.t('daily_acc_reloj');
    case AccessoryType.gafas:
      return t.t('daily_acc_gafas');
    case AccessoryType.gorra:
      return t.t('daily_acc_gorra');
    case AccessoryType.pulsera:
      return t.t('daily_acc_pulsera');
    case AccessoryType.cinturon:
      return t.t('daily_acc_cinturon');
  }
}

/// Pestaña "Outfit del día": consulta el tiempo real (ver [WeatherService])
/// y, junto con la ocasión que elija el usuario, genera una única
/// recomendación con el motor de reglas local (`OutfitRecommendationService`,
/// el mismo que usa la pestaña Outfits para sus sugerencias con IA).
///
/// Sustituye a la antigua pestaña "Planificador" en la navegación principal
/// (ver `MainNavigation` en `main.dart`); también reemplaza a la tarjeta
/// "Sugerencia del Día" que antes vivía en `outfit_screen.dart`, que ahora
/// solo se ocupa de explorar/generar outfits en general.
class DailyOutfitScreen extends StatefulWidget {
  const DailyOutfitScreen({super.key, @visibleForTesting this.random});

  /// Fuente de azar para el sorteo ponderado de la sugerencia principal (ver
  /// `OutfitMatchingService.generate`). `null` en producción → se crea un
  /// `Random()` real. Los tests inyectan un `Random(semilla)` para que la
  /// generación sea reproducible.
  final Random? random;

  @override
  State<DailyOutfitScreen> createState() => _DailyOutfitScreenState();
}

class _DailyOutfitScreenState extends State<DailyOutfitScreen> {
  late final Random _rng = widget.random ?? Random();

  /// El clima y la ubicación viven en [LocationProvider] (fuente única para
  /// toda la app). Esta pantalla lo escucha: cuando el usuario cambia de
  /// ciudad en Ajustes/onboarding o pulsa "Actualizar", el provider vuelve a
  /// consultar el tiempo y aquí se regenera el outfit con la nueva temperatura.
  late final LocationProvider _location = context.read<LocationProvider>();

  /// Se escucha para volver a redactar la descripción del outfit en el idioma
  /// nuevo cuando el usuario lo cambia en Ajustes (ver [_onLocaleChanged]).
  late final LocaleProvider _locale = context.read<LocaleProvider>();

  /// Código de idioma con el que se generó el outfit actual. Si cambia, hay
  /// que regenerar para que `explanation` salga en ese idioma.
  String? _generatedForLanguage;

  /// Último [WeatherReport] para el que ya se generó un outfit, para no
  /// regenerar en cada `notifyListeners` (p. ej. al alternar el `loading`).
  WeatherReport? _generatedForWeather;

  OutfitOccasion? _occasion;
  DailyOutfitCategoryOption? _lockedCategory;

  /// Sección "Accesorios": completamente independiente de [_lockedCategory]
  /// (ver el comentario de [DailyOutfitCategoryOption]) y de selección
  /// múltiple — el usuario puede marcar uno, varios o ninguno de
  /// [_dailyOutfitAccessoryTypes] a la vez. [_accessoriesEnabled] solo
  /// controla si el grid de sub-chips está desplegado; al desactivarlo se
  /// limpia la selección para que, si se vuelve a activar, empiece en
  /// blanco. Mientras está activo (aunque no haya nada marcado todavía),
  /// [_generateOutfit] pasa la selección explícita al motor en vez de su
  /// elección automática por defecto — ver `selectedAccessories` ahí.
  bool _accessoriesEnabled = false;
  final Set<AccessoryType> _selectedAccessoryTypes = {};

  bool _outfitLoading = false;
  String? _outfitError;
  OutfitRecommendation? _outfit;

  @override
  void initState() {
    super.initState();
    _location.addListener(_onLocationChanged);
    _locale.addListener(_onLocaleChanged);
    // Si el tiempo ya estaba cargado (el provider se creó antes, p. ej. desde
    // el onboarding), genera el primer outfit ya; si no, lo hará
    // `_onLocationChanged` en cuanto llegue la temperatura.
    final report = _location.weather;
    if (report != null) {
      _generatedForWeather = report;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _regenerateForWeather();
      });
    }
  }

  @override
  void dispose() {
    _location.removeListener(_onLocationChanged);
    _locale.removeListener(_onLocaleChanged);
    super.dispose();
  }

  /// Al cambiar el idioma de la app, regenera el outfit para que su
  /// descripción (`OutfitRecommendation.explanation`) salga redactada en el
  /// idioma nuevo — ver el parámetro `l10n` de
  /// `OutfitRecommendationService.generate`.
  void _onLocaleChanged() {
    if (!mounted || _location.weather == null) return;
    if (_locale.languageCode == _generatedForLanguage) return;
    unawaited(_generateOutfit());
  }

  /// Reacciona a los cambios de [LocationProvider]: si hay una temperatura
  /// NUEVA (cambio de ciudad, "Actualizar", primera carga) regenera el outfit.
  /// El estado de carga/error del clima lo refleja `build` por su cuenta
  /// (`context.watch`), así que aquí solo interesa el disparo de generación.
  void _onLocationChanged() {
    if (!mounted) return;
    final report = _location.weather;
    if (report != null && !identical(report, _generatedForWeather)) {
      _generatedForWeather = report;
      _regenerateForWeather();
    }
  }

  void _regenerateForWeather() {
    // Rota la parte superior si una sesión anterior dejó historial: así no
    // reaparece el outfit de ayer. Instalación nueva → sin historial → sin
    // rotación, nada que evitar.
    unawaited(
      _generateOutfit(rotateTop: context.read<OutfitHistoryProvider>().hasHistory),
    );
  }

  /// Se dispara automáticamente en cuanto hay tiempo disponible y cada vez
  /// que cambia la ocasión, la categoría fija o se pulsa "Generar Nuevo
  /// Outfit": no hace falta esperar a nada más, el outfit del día se
  /// recalcula solo, como el propio nombre de la pantalla promete.
  ///
  /// `OutfitMatchingService.generate` usa la ocasión SOLO como bonus de
  /// puntuación (nunca como filtro duro), así que en un armario pequeño o de
  /// un único estilo la prenda ganadora podía quedar clavada aunque el
  /// usuario cambiara de chip. Para que la ocasión (y la categoría fija) se
  /// noten de verdad, se intenta en cascada con armarios cada vez menos
  /// restringidos (`wardrobeCandidates`), del más fiel al contexto elegido
  /// (temperatura real + ocasión) al armario completo, quedándose con el
  /// primero que dé alguna recomendación válida:
  ///
  ///  1. Prendas dentro de rango de temperatura (los °C de
  ///     `LocationProvider.weather`, vía
  ///     [OutfitRecommendationService.filterGarmentsByTemperature]) Y del
  ///     estilo de la ocasión elegida, con `strictTops` además.
  ///  2. Igual que 1 sin `strictTops`.
  ///  3. Solo por ocasión (temperatura fuera de rango pero se prioriza no
  ///     dejar sin outfit al usuario).
  ///  4. Solo por temperatura (sin restringir por ocasión).
  ///  5. Armario completo, sin restricción.
  ///
  /// El último nivel (armario completo) SIEMPRE da resultado si el armario
  /// tiene al menos una parte superior, un pantalón y un calzado: el motor
  /// cae a su fallback por proximidad (ver "Garantía de resultado" en
  /// `OutfitMatchingService.generate`) y devuelve la combinación más parecida
  /// en vez de un hueco vacío. El `catch` de abajo solo se activa cuando falta
  /// una de esas tres categorías por completo.
  ///
  /// Si hay una categoría fija ([_lockedCategory]), el filtro de temperatura
  /// de los pasos 1 y 3 exime a las prendas de esa categoría (parámetro
  /// `exempt` de `filterGarmentsByTemperature`) para que ni siquiera llegue a
  /// descartarse de los armarios candidatos — pero eso por sí solo NO basta:
  /// `OutfitMatchingService.generate` en modo normal sigue teniendo filtros
  /// duros de compatibilidad (color/estilo/temporada) y de layering
  /// ("sudadera nunca sola") que podían rechazar igualmente cualquier combo
  /// que la incluyera, dejando al usuario con el mismo error aunque la
  /// prenda sí sobreviviera al filtro de temperatura. Por eso cada intento
  /// pasa también `lockedMatch: category?.matches` y `currentTemp` (ver
  /// `OutfitRecommendationService.generate`/`OutfitMatchingService.generate`):
  /// con `lockedMatch` activo, el motor SIEMPRE incluye una prenda de esa
  /// categoría en cuanto exista al menos una en el armario que se le pase, y
  /// puntúa el resto del look (afinidad de color/temperatura/ocasión) en vez
  /// de descartarlo por incompatibilidad — así que, en la práctica, ya el
  /// primer intento de la cascada que contenga alguna prenda de la categoría
  /// (los cuatro suelen tenerla, salvo que el filtro por ocasión la excluya)
  /// tiene éxito. El post-filtro `r.garments.any(category.matches)` se deja
  /// como comprobación defensiva: con `lockedMatch` nunca debería descartar
  /// nada, pero documenta la garantía sin depender de detalles internos del
  /// motor. Solo si el armario no tiene NINGUNA prenda de esa categoría (o le
  /// falta un hueco estructural: parte superior, pantalón o calzado) se
  /// muestra el error específico.
  ///
  /// Por último, si el resultado elegido coincide exactamente con el outfit
  /// ya mostrado, se prueba con la siguiente sugerencia de la lista: el
  /// usuario ve un cambio en pantalla en cuanto exista una alternativa real,
  /// en vez de la misma combinación repetida sin explicación.
  ///
  /// [rotateTop] (activo en cada cambio de parámetro de la UI y en el botón
  /// "Generar Nuevo Outfit") excluye ACTIVAMENTE todas las prendas del outfit
  /// anterior, para que el nuevo sea distinto pieza a pieza siempre que el
  /// armario lo permita. La exclusión es "blanda": si dejar fuera una prenda
  /// vaciara un hueco (p. ej. el único pantalón), el motor la restaura en vez
  /// de fallar (ver `excludeGarmentIds` en `OutfitMatchingService.generate`).
  /// Se combina con el "cooldown" de [OutfitHistoryProvider] (penalización
  /// suave de las prendas de las últimas sugerencias) y con el sorteo ponderado
  /// del motor ([_rng]). La primera generación de la sesión también rota si una
  /// sesión anterior dejó historial (así no reaparece el outfit de ayer).
  Future<void> _generateOutfit({bool rotateTop = false}) async {
    final weather = _location.weather;
    if (weather == null) return;

    setState(() {
      _outfitLoading = true;
      _outfitError = null;
    });

    final t = AppLocalizations.of(context);
    final occasion = _occasion;
    final category = _lockedCategory;
    final history = context.read<OutfitHistoryProvider>();
    final fullWardrobe = context.read<WardrobeProvider>().garments;
    final tempAppropriate = OutfitRecommendationService.filterGarmentsByTemperature(
      garments: fullWardrobe,
      currentTemp: weather.temperatureCelsius,
      // La prenda/categoría fijada por el usuario nunca se descarta por
      // temperatura: la pidió a propósito, así que debe poder aparecer en
      // el outfit aunque esté fuera de su rango ideal para el tiempo de hoy.
      exempt: category?.matches,
    );

    // Señales anti-repetición. `previousIds` = prendas del outfit anterior (el
    // que hay en pantalla o, en la primera generación de la sesión, el último
    // registrado). Con `rotateTop` se excluyen TODAS de forma blanda (el motor
    // restaura las que vaciarían un hueco); siempre, además, penalizan la
    // puntuación vía `previousOutfitIds`. `recentIds` añade el cooldown de las
    // últimas sugerencias, sin duplicar las del outfit anterior.
    final previousIds =
        _outfit != null ? _garmentIds(_outfit!) : history.lastOutfitGarmentIds;
    final excludeIds = rotateTop ? previousIds : const <String>{};
    final recentIds = history.recentGarmentIds(lookback: 5).difference(previousIds);

    List<Garment> byOccasion(List<Garment> wardrobe) => occasion == null
        ? wardrobe
        : wardrobe.where((g) => g.style == _styleForOccasion(occasion)).toList();

    // Cascada del armario más fiel al contexto al armario completo. El primer
    // intento estrena un filtro ESTRICTO de la parte superior (estilo de
    // ocasión + temporada + rango de temperatura, sin exención de tipo nulo);
    // si no da resultado, `generate` lanza y se cae al mismo nivel sin
    // estricto — que es exactamente la cascada de siempre.
    final wardrobeCandidates = <({List<Garment> wardrobe, bool strict})>[
      (wardrobe: byOccasion(tempAppropriate), strict: true),
      (wardrobe: byOccasion(tempAppropriate), strict: false),
      (wardrobe: byOccasion(fullWardrobe), strict: false),
      (wardrobe: tempAppropriate, strict: false),
      (wardrobe: fullWardrobe, strict: false),
    ];

    Future<List<OutfitRecommendation>> attempt(List<Garment> wardrobe, bool strict) {
      return OutfitRecommendationService.generate(
        wardrobe,
        occasion: occasion,
        weather: weather.condition,
        // Con categoría fija se piden más candidatos: más variedad entre la
        // que elegir (ver `chosen` más abajo), aunque ya no hace falta para
        // garantizar que la categoría aparezca (ver `lockedMatch`).
        count: category == null ? 3 : 8,
        // Garantiza que la categoría fija aparezca en el outfit generado a
        // partir de este armario, saltándose los filtros duros de
        // compatibilidad/layering que la bloqueaban antes (ver el
        // comentario de [_generateOutfit]). `currentTemp` alimenta la
        // puntuación de temperatura del resto del look cuando hay lock;
        // fuera de modo lock no se usa.
        lockedMatch: category?.matches,
        currentTemp: weather.temperatureCelsius,
        // `null` cuando la sección de Accesorios está desactivada preserva
        // el comportamiento de siempre (el motor elige hasta 2 accesorios
        // compatibles por su cuenta). Activa, la selección del usuario manda
        // por completo — incluida una lista vacía si activó la sección pero
        // no marcó ningún sub-chip todavía (cero accesorios a propósito).
        selectedAccessories: _accessoriesEnabled ? _selectedAccessoryTypes.toList() : null,
        excludeGarmentIds: excludeIds,
        recentGarmentIds: recentIds,
        previousOutfitIds: previousIds,
        strictTops: strict,
        random: _rng,
        // Redacta la explicación del outfit en el idioma activo de la app.
        l10n: t,
      );
    }

    try {
      List<OutfitRecommendation>? found;
      for (final candidate in wardrobeCandidates) {
        if (candidate.wardrobe.isEmpty) continue;
        List<OutfitRecommendation> recommendations;
        try {
          recommendations = await attempt(candidate.wardrobe, candidate.strict);
        } catch (_) {
          continue;
        }
        final filtered = category == null
            ? recommendations
            : recommendations.where((r) => r.garments.any(category.matches)).toList();
        if (filtered.isNotEmpty) {
          found = filtered;
          break;
        }
      }

      if (found == null) {
        // Con el fallback por proximidad del motor, la cascada solo se queda
        // sin resultado si al armario le falta un hueco estructural entero
        // (sin ninguna parte superior, sin pantalón o sin calzado), o si se
        // fijó una categoría de la que no hay ninguna prenda. Nunca por lo
        // restrictivos que sean los filtros de clima u ocasión.
        throw Exception('structural-gap');
      }

      final chosen = found.firstWhere(
        // Salta la sugerencia cuyo conjunto de prendas es idéntico al que ya
        // está en pantalla; `previousIds` vacío (aún no hay outfit) nunca
        // coincide con una rec real.
        (r) => !setEquals(_garmentIds(r), previousIds),
        orElse: () => found!.first,
      );

      if (!mounted) return;
      _generatedForLanguage = t.locale.languageCode;
      setState(() {
        _outfit = chosen;
        _outfitLoading = false;
      });
      // Fire-and-forget: `_entries` se actualiza en memoria de forma síncrona,
      // así que una regeneración inmediata ya ve esta entrada aunque el
      // guardado en disco siga en curso.
      unawaited(
        history.recordOutfit(
          chosen.garments.map((g) => g.id).toList(),
          topId: _baseTopId(chosen),
        ),
      );
    } catch (e) {
      debugPrint('[DailyOutfitScreen] No se pudo generar el outfit del día: $e');
      if (!mounted) return;
      setState(() {
        _outfit = null;
        // El motor ya siempre devuelve el outfit más parecido cuando los
        // filtros de clima/ocasión aprietan (fallback por proximidad), así que
        // este aviso es solo para lo que de verdad no se puede resolver
        // combinando: que falte una categoría entera en el armario.
        _outfitError = category != null
            ? t.t('daily_need_category', {'category': category.label(t)})
            : t.t('daily_need_top_bottom_shoes');
        _outfitLoading = false;
      });
    }
  }

  void _selectOccasion(OutfitOccasion? occasion) {
    HapticFeedback.selectionClick();
    setState(() => _occasion = occasion);
    unawaited(_generateOutfit(rotateTop: true));
  }

  void _selectCategory(DailyOutfitCategoryOption? category) {
    HapticFeedback.selectionClick();
    setState(() => _lockedCategory = category);
    unawaited(_generateOutfit(rotateTop: true));
  }

  /// Activa/desactiva la sección de Accesorios. A propósito NO toca
  /// [_lockedCategory]: son selecciones independientes (ver el comentario de
  /// [_accessoriesEnabled]).
  void _toggleAccessoriesEnabled() {
    HapticFeedback.selectionClick();
    setState(() {
      _accessoriesEnabled = !_accessoriesEnabled;
      if (!_accessoriesEnabled) _selectedAccessoryTypes.clear();
    });
    unawaited(_generateOutfit(rotateTop: true));
  }

  /// Marca/desmarca un tipo de accesorio dentro de la selección múltiple. A
  /// propósito NO toca [_lockedCategory] (ver el comentario de
  /// [_accessoriesEnabled]).
  void _toggleAccessoryType(AccessoryType type) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selectedAccessoryTypes.remove(type)) {
        _selectedAccessoryTypes.add(type);
      }
    });
    unawaited(_generateOutfit(rotateTop: true));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    // Se observa el armario para que, si el usuario añade o borra una prenda
    // sin salir de esta pestaña, el próximo cambio de ocasión (o un tirón de
    // "Actualizar" en el tiempo) ya use el armario al día.
    context.watch<WardrobeProvider>();
    // Y la ubicación/clima: cambiar de ciudad en Ajustes o pulsar "Actualizar"
    // refresca la temperatura en pantalla al instante (y `_onLocationChanged`
    // regenera el outfit con esa temperatura).
    final location = context.watch<LocationProvider>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.t('daily_title'),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  // Con el tiempo ya cargado (`location.weather != null`), esta
                  // tarjeta se omite: la temperatura pasa a mostrarse dentro
                  // de la cabecera de `DailyOutfitFlatLayCard`
                  // (`_WeatherBadge`, junto a "Outfit Sugerido."), y
                  // mostrarla dos veces era redundante. Se conserva solo
                  // para los estados de carga/error, donde todavía no hay
                  // ninguna tarjeta de outfit con la que duplicarse.
                  if (location.weather == null) ...[
                    _WeatherCard(
                      loading: location.weatherLoading,
                      error: location.weatherError,
                      weather: location.weather,
                      onRetry: () => unawaited(location.refreshWeather()),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    t.t('daily_occasion'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(t.t('daily_any')),
                        selected: _occasion == null,
                        onSelected: (_) => _selectOccasion(null),
                      ),
                      for (final occasion in OutfitOccasion.values)
                        ChoiceChip(
                          label: Text(t.occasion(occasion)),
                          selected: _occasion == occasion,
                          onSelected: (_) => _selectOccasion(occasion),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _OutfitOfDaySection(
                    weather: location.weather,
                    loading: _outfitLoading,
                    error: _outfitError,
                    outfit: _outfit,
                    lockedCategory: _lockedCategory,
                    onRetry: () => unawaited(_generateOutfit(rotateTop: true)),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    t.t('daily_include_specific'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CategoryOptionChip(
                        label: t.t('daily_any'),
                        selected: _lockedCategory == null,
                        onTap: () => _selectCategory(null),
                      ),
                      for (final category in DailyOutfitCategoryOption.values)
                        _CategoryOptionChip(
                          label: category.label(t),
                          selected: _lockedCategory == category,
                          onTap: () => _selectCategory(category),
                        ),
                      // Chip independiente de `_lockedCategory` a propósito
                      // (ver el comentario de [DailyOutfitCategoryOption]):
                      // activarlo no desmarca la prenda principal fijada, ni
                      // al revés.
                      _CategoryOptionChip(
                        label: t.t('daily_accessories'),
                        selected: _accessoriesEnabled,
                        onTap: _toggleAccessoriesEnabled,
                      ),
                    ],
                  ),
                  if (_accessoriesEnabled) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type in _dailyOutfitAccessoryTypes)
                          _CategoryOptionChip(
                            label: _dailyOutfitAccessoryLabel(t, type),
                            selected: _selectedAccessoryTypes.contains(type),
                            onTap: () => _toggleAccessoryType(type),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: (location.weather == null || _outfitLoading)
                          ? null
                          : () {
                              HapticFeedback.mediumImpact();
                              unawaited(_generateOutfit(rotateTop: true));
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        t.t('daily_generate_new'),
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip en forma de píldora para la sección "¿Quieres incluir algo
/// específico?": mismo patrón que `_FilterChip` de `outfit_screen.dart`
/// (colores de tema, no hex literales, para que el dark mode siga
/// funcionando), pero con `StadiumBorder` explícito para el look de píldora
/// del diseño "Flat Lay".
class _CategoryOptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryOptionChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? scheme.onPrimary : scheme.onSurface,
      ),
      shape: StadiumBorder(
        side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    );
  }
}

/// Tarjeta del tiempo actual: shimmer mientras carga, aviso con reintento si
/// falla la llamada a [WeatherService], o icono+temperatura+descripción con
/// un botón para refrescar manualmente.
class _WeatherCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final WeatherReport? weather;
  final VoidCallback onRetry;

  const _WeatherCard({
    required this.loading,
    required this.error,
    required this.weather,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.cardBeige,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardHairlineColor(context)),
        boxShadow: cardElevation(context, strength: 0.6),
      ),
      child: _content(context, palette, scheme),
    );
  }

  Widget _content(BuildContext context, AppPalette palette, ColorScheme scheme) {
    final t = AppLocalizations.of(context);
    // "Sin dato todavía" (ni cargando, ni error, ni tiempo) se trata como
    // carga: es el hueco breve entre que `LocationProvider` lee la ubicación y
    // arranca la consulta del tiempo (y el estado en el que queda un test que
    // monta el provider sin `autoLoad`).
    if (loading || (weather == null && error == null)) {
      return const Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: ShimmerBox(borderRadius: BorderRadius.all(Radius.circular(20))),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShimmerBox(height: 18, width: 90),
                SizedBox(height: 8),
                ShimmerBox(height: 13, width: 130),
              ],
            ),
          ),
        ],
      );
    }

    if (error != null) {
      return Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: scheme.error, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              t.t(error!),
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            tooltip: t.t('common_retry'),
          ),
        ],
      );
    }

    final report = weather!;
    return Row(
      children: [
        Icon(report.icon, size: 38, color: scheme.secondary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${report.temperatureCelsius.round()}°C',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: palette.strongText,
                ),
              ),
              const SizedBox(height: 2),
              Text(t.t(report.descriptionKey),
                  style: TextStyle(color: palette.textSecondary)),
            ],
          ),
        ),
        IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          tooltip: t.t('daily_weather_update'),
        ),
      ],
    );
  }
}

/// Cuerpo principal de la pantalla: la recomendación en sí, o el estado que
/// corresponda (esperando el tiempo, cargando, error, o el aviso que ya trae
/// [OutfitRecommendationService] cuando el armario no da para generar nada).
class _OutfitOfDaySection extends StatelessWidget {
  final WeatherReport? weather;
  final bool loading;
  final String? error;
  final OutfitRecommendation? outfit;
  final DailyOutfitCategoryOption? lockedCategory;
  final VoidCallback onRetry;

  const _OutfitOfDaySection({
    required this.weather,
    required this.loading,
    required this.error,
    required this.outfit,
    required this.lockedCategory,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (weather == null) {
      return _MessageCard(
        icon: Icons.hourglass_top_outlined,
        message: t.t('daily_waiting_weather'),
      );
    }

    if (loading) {
      return const _LoadingOutfitCard();
    }

    if (error != null) {
      return _MessageCard(
        icon: Icons.error_outline,
        message: error!,
        isError: true,
        onRetry: onRetry,
      );
    }

    final recommendation = outfit;
    if (recommendation == null) {
      return _MessageCard(
        icon: Icons.checkroom_outlined,
        message: t.t('daily_no_outfit_yet'),
      );
    }

    return DailyOutfitFlatLayCard(
      outfit: recommendation,
      weather: weather!,
      lockedCategory: lockedCategory,
    );
  }
}

/// Tarjeta "Flat Lay" del outfit sugerido: cabecera (título + insignia de
/// clima) y mosaico de tarjetas individuales por prenda (`BoxFit.contain`
/// sobre fondo neutro, efecto collage de foto de producto), con la prenda
/// que corresponde a [lockedCategory] resaltada con borde verde salvia.
///
/// `GridView` de 2 columnas en vez de un `Row`/`Column` fijo a un número de
/// huecos concreto: un outfit puede traer desde 3 prendas (parte superior +
/// pantalón + calzado) hasta más de 10 (layering de hasta 3 capas
/// superiores + pantalón + calzado + hasta los 6 tipos de accesorio de la
/// sección "Accesorios", si el usuario los marca todos — ver
/// `OutfitMatchingService`/`selectedAccessories`), así que el número de
/// filas se adapta solo sin ningún límite fijo en la propia tarjeta.
class DailyOutfitFlatLayCard extends StatelessWidget {
  final OutfitRecommendation outfit;
  final WeatherReport weather;
  final DailyOutfitCategoryOption? lockedCategory;

  const DailyOutfitFlatLayCard({
    super.key,
    required this.outfit,
    required this.weather,
    this.lockedCategory,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final t = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      // Fondo del CONTENEDOR EXTERNO en el lienzo neutro de foto de prenda
      // (`garmentPhotoBackground`, ya usado para ese mismo propósito en
      // `add_garment_screen.dart`), a propósito más claro que
      // `palette.cardBeige` de cada tarjeta interior: si ambos compartieran
      // color, las tarjetas de prenda del mosaico se fundirían con el
      // contenedor y perderían su efecto de "tarjeta individual".
      decoration: BoxDecoration(
        color: palette.garmentPhotoBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cardHairlineColor(context)),
        boxShadow: cardElevation(context, strength: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.t('daily_suggested_outfit'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: palette.strongText,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _FavoriteOutfitButton(outfit: outfit),
              const SizedBox(width: 4),
              _WeatherBadge(weather: weather),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              // Tarjetas más altas que anchas (antes 1 = cuadradas): con la
              // tarjeta de la cabecera de tiempo ya eliminada de fuera (ver
              // más arriba), el mosaico gana protagonismo ocupando más
              // superficie vertical de la pantalla.
              childAspectRatio: 0.85,
            ),
            itemCount: outfit.garments.length,
            itemBuilder: (context, i) {
              final garment = outfit.garments[i];
              final highlighted = lockedCategory?.matches(garment) ?? false;
              return _FlatLayGarmentTile(garment: garment, highlighted: highlighted);
            },
          ),
          const SizedBox(height: 14),
          Text(
            outfit.explanation,
            style: TextStyle(color: palette.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// Botón de corazón de la cabecera de [DailyOutfitFlatLayCard]: guarda o quita
/// el outfit sugerido de la pestaña "Favoritos". Es un toggle inmediato (un
/// toque guarda, otro quita), identificando el favorito por el conjunto de
/// prendas del outfit (ver [FavoriteOutfitsProvider.favoriteFor]).
class _FavoriteOutfitButton extends StatelessWidget {
  final OutfitRecommendation outfit;

  const _FavoriteOutfitButton({required this.outfit});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final t = AppLocalizations.of(context);
    final favorites = context.watch<FavoriteOutfitsProvider>();
    final ids = _garmentIds(outfit).toList();
    final isFavorite = favorites.isFavorite(ids);

    return IconButton(
      onPressed: () async {
        final provider = context.read<FavoriteOutfitsProvider>();
        final existing = provider.favoriteFor(ids);
        if (existing != null) {
          await provider.removeFavoriteOutfit(existing.id);
        } else {
          await provider.addFavoriteOutfit(
            garmentIds: ids,
            tags: _autoTags(outfit),
            occasion: outfit.occasion,
          );
        }
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          existing != null
              ? t.t('daily_removed_from_fav')
              : t.t('daily_saved_to_fav'),
        );
      },
      icon: Icon(
        isFavorite ? Icons.favorite : Icons.favorite_border,
        color: isFavorite ? palette.favoritePinkText : palette.iconMuted,
      ),
      tooltip: isFavorite
          ? t.t('daily_remove_from_fav')
          : t.t('daily_add_to_fav'),
    );
  }
}

/// Insignia compacta de clima (icono + temperatura) para la cabecera de
/// [DailyOutfitFlatLayCard]. Reutiliza el mismo [WeatherReport] que ya
/// muestra la tarjeta del tiempo de arriba (`_WeatherCard`): esta insignia
/// solo se pinta cuando ya hay un outfit generado, o sea cuando el tiempo ya
/// cargó con éxito, así que no necesita su propio estado de carga/error.
class _WeatherBadge extends StatelessWidget {
  final WeatherReport weather;

  const _WeatherBadge({required this.weather});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chipBeige,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(weather.icon, size: 16, color: scheme.secondary),
            const SizedBox(width: 4),
            Text(
              '${weather.temperatureCelsius.round()}°C',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.strongText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una prenda del mosaico "Flat Lay": tarjeta rectangular sobre fondo
/// neutro con la foto en `BoxFit.contain` (nunca recortada ni deformada —
/// `BoxFit.cover` no vale aquí: recortaría la prenda en vez de mostrarla
/// entera, que es el punto de un mosaico tipo foto de producto), con borde
/// verde salvia destacado cuando corresponde a la categoría fija elegida
/// por el usuario ([DailyOutfitCategoryOption]).
///
/// La foto se pinta con [AutocroppedGarment] (de `outfit_flat_lay_view.dart`,
/// reutilizado tal cual aquí) en vez de [GarmentImage] directamente: `Garment`
/// solo guarda UNA foto por prenda (`imagePath`, ya sin fondo — el recorte de
/// fondo ocurre antes de guardar, ver `add_garment_screen.dart` /
/// `U2NetSegmentationService`; no existe un campo aparte de "imagen original
/// con fondo" del que distinguirla). Pero esa foto
/// conserva el encuadre original: si la prenda ocupaba poco espacio dentro de
/// la foto de cámara, el margen alrededor queda transparente en vez de
/// desaparecer, y se ve pequeña dentro de su recuadro aunque el fondo ya no
/// esté. [AutocroppedGarment] recorta ese margen transparente sobrante al
/// bounding box real de píxeles visibles (vía `GarmentAutocropCache`,
/// cacheado por prenda) antes de pintar, con el mismo respaldo seguro a la
/// foto sin recortar si el recorte falla.
///
/// Padding mínimo (4, antes 10): con `BoxFit.contain` la imagen ya respeta
/// su proporción sola sin deformarse, así que no hace falta un margen grande
/// para evitar que "toque" el borde — un padding pequeño le da a la prenda
/// el máximo espacio posible dentro del rectángulo redondeado mientras
/// conserva un margen sutil entre la imagen y el borde de la tarjeta.
class _FlatLayGarmentTile extends StatelessWidget {
  final Garment garment;
  final bool highlighted;

  const _FlatLayGarmentTile({required this.garment, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: palette.cardBeige,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? scheme.primary : cardHairlineColor(context),
          width: highlighted ? 2.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: AutocroppedGarment(imagePath: garment.imagePath),
    );
  }
}

class _LoadingOutfitCard extends StatelessWidget {
  const _LoadingOutfitCard();

  @override
  Widget build(BuildContext context) {
    return const ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(20)),
      child: SizedBox(height: 320, child: ShimmerBox(borderRadius: BorderRadius.zero)),
    );
  }
}

/// Aviso neutro (sin outfit que mostrar todavía) o de error (con reintento
/// opcional), reutilizado tanto por el tiempo como por la recomendación.
class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool isError;
  final VoidCallback? onRetry;

  const _MessageCard({
    required this.icon,
    required this.message,
    this.isError = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : palette.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isError ? scheme.error.withValues(alpha: 0.08) : palette.cardBeige,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isError ? scheme.error.withValues(alpha: 0.25) : cardHairlineColor(context),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.w500),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).t('common_retry')),
            ),
          ],
        ],
      ),
    );
  }
}
