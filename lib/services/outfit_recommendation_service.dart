import 'dart:math';

import '../l10n/app_localizations.dart';
import '../models/garment.dart';
import '../models/outfit_filters.dart';
import '../models/tipo_prenda.dart';
import 'outfit_matching_service.dart';

/// Una combinación de outfit sugerida por el motor de reglas local a partir
/// de las prendas reales del armario del usuario.
class OutfitRecommendation {
  final String title;
  final String occasion;
  final String explanation;
  final List<Garment> garments;

  const OutfitRecommendation({
    required this.title,
    required this.occasion,
    required this.explanation,
    required this.garments,
  });
}

class OutfitRecommendationService {
  /// Genera combinaciones de outfits válidas usando únicamente las prendas
  /// del armario, con [OutfitMatchingService] (motor de reglas 100% local:
  /// sin red, sin IA). Lanza [Exception] si el armario no tiene prendas
  /// suficientes para armar ninguna combinación.
  /// [lockedMatch], [currentTemp], [selectedAccessories], [excludeGarmentIds],
  /// [recentGarmentIds], [previousOutfitIds], [strictTops], [random] y [l10n]
  /// (idioma de la `explanation`) se
  /// reenvían tal cual a [OutfitMatchingService.generate]: ver la
  /// documentación de ese método (garantía de "prenda/categoría fijada",
  /// selección múltiple de accesorios, cooldown/rotación anti-repetición y
  /// sorteo ponderado). Todos los parámetros anti-repetición tienen un valor
  /// por defecto que reproduce el comportamiento anterior.
  static Future<List<OutfitRecommendation>> generate(
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
  }) async {
    if (garments.isEmpty) {
      throw Exception('Añade prendas al armario antes de generar outfits.');
    }

    return OutfitMatchingService.generate(
      garments,
      occasion: occasion,
      weather: weather,
      count: count,
      lockedMatch: lockedMatch,
      currentTemp: currentTemp,
      selectedAccessories: selectedAccessories,
      excludeGarmentIds: excludeGarmentIds,
      recentGarmentIds: recentGarmentIds,
      previousOutfitIds: previousOutfitIds,
      strictTops: strictTops,
      random: random,
      l10n: l10n,
    );
  }

  /// Filtra el armario a las prendas adecuadas para [currentTemp] (°C),
  /// según el rango [TipoPrenda.tempMin]/[TipoPrenda.tempMax] del tipo con el
  /// que se guardó cada una (`Garment.tipoPrendaId`).
  ///
  /// Una prenda sin [Garment.tipoPrendaId] (guardada antes de que existiera
  /// este campo) o cuyo id ya no aparece en [tiposDePrenda] se conserva sin
  /// filtrar: no hay dato de temperatura del que fiarse, y ocultar prendas
  /// del armario del usuario por falta de metadatos sería peor que no
  /// filtrarlas.
  ///
  /// [exempt] deja pasar una prenda SIN comprobar su rango de temperatura,
  /// aunque tenga [Garment.tipoPrendaId] y esté fuera de rango: lo usa
  /// `daily_outfit_screen.dart` para la categoría/prenda que el usuario haya
  /// fijado a propósito (p. ej. `DailyOutfitCategoryOption.matches`) — esa
  /// prenda debe aparecer en el outfit aunque no sea la ideal para el tiempo
  /// de hoy, mientras que el resto del armario (lo que la acompañe) sigue
  /// filtrándose con normalidad.
  static List<Garment> filterGarmentsByTemperature({
    required List<Garment> garments,
    required double currentTemp,
    bool Function(Garment garment)? exempt,
  }) {
    return garments.where((garment) {
      if (exempt != null && exempt(garment)) return true;
      final tipo = _tipoPrendaOf(garment);
      if (tipo == null) return true;
      return currentTemp >= tipo.tempMin && currentTemp <= tipo.tempMax;
    }).toList();
  }

  static TipoPrenda? _tipoPrendaOf(Garment garment) {
    final id = garment.tipoPrendaId;
    if (id == null) return null;
    for (final tipo in tiposDePrenda) {
      if (tipo.id == id) return tipo;
    }
    return null;
  }
}
