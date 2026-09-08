import '../models/garment.dart';
import '../models/outfit_filters.dart';
import '../models/tipo_prenda.dart';
import 'app_localizations.dart';

/// Etiquetas localizadas de los enums del dominio. Reemplazan a los getters
/// `.label` (que siguen existiendo en español como respaldo para las pantallas
/// aún sin traducir). Las claves siguen el nombre del `enum` value, así que
/// añadir un valor nuevo solo pide una clave nueva en los dos JSON.
extension L10nEnums on AppLocalizations {
  String occasion(OutfitOccasion value) => t('occasion_${value.name}');
  String weatherCondition(WeatherCondition value) => t('wcond_${value.name}');
  String style(GarmentStyle value) => t('style_${value.name}');
  String season(GarmentSeason value) => t('season_${value.name}');
  String category(GarmentCategory value) => t('category_${value.name}');
  String superCategory(GarmentSuperCategory value) => t('supercat_${value.name}');
  String accessoryType(AccessoryType value) => t('accessory_${value.name}');
  String grupoPrenda(GrupoPrenda value) => t('grupo_${value.name}');
}
