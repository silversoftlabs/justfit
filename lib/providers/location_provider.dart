import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/place_search_service.dart';
import '../services/weather_service.dart';

/// Firma del "traedor de tiempo" que usa [LocationProvider]. En producción es
/// `WeatherService.fetchAt`; los tests inyectan un doble para no depender de
/// la red.
typedef WeatherFetcher = Future<WeatherReport> Function({
  required double latitude,
  required double longitude,
});

/// Fuente única de la ubicación del usuario y del tiempo asociado. Sustituye
/// al estado de clima que `DailyOutfitScreen` llevaba en local: al cambiar la
/// ubicación (onboarding o Ajustes) invalida la temperatura anterior y vuelve
/// a consultar WeatherAPI de inmediato, y como es un [ChangeNotifier] la
/// pantalla y sus tarjetas de clima se refrescan solas.
///
/// Persiste en `SharedPreferences`:
///  - `onboarding_location`     — nombre corto ("Madrid"), compatible con lo
///     que ya guardaba el onboarding y con `WeatherService._resolveCoordinates`.
///  - `location_display_name`   — etiqueta completa para la UI.
///  - `weather_cached_lat` / `weather_cached_lon` / `weather_cached_place` —
///     las mismas claves de caché de coordenadas de `WeatherService`, para que
///     ambos vean siempre lo mismo.
class LocationProvider extends ChangeNotifier {
  static const _nameKey = 'onboarding_location';
  static const _displayKey = 'location_display_name';
  static const _latKey = 'weather_cached_lat';
  static const _lonKey = 'weather_cached_lon';
  static const _cachedPlaceKey = 'weather_cached_place';

  final WeatherFetcher _fetchWeather;

  /// `autoLoad: false` (solo tests): no lee prefs ni consulta el tiempo al
  /// construirse, así el widget bajo test no dispara peticiones de red.
  LocationProvider({bool autoLoad = true, WeatherFetcher? weatherFetcher})
      : _fetchWeather = weatherFetcher ?? WeatherService.fetchAt {
    if (autoLoad) _init();
  }

  String? _name;
  String? _displayName;
  double? _lat;
  double? _lon;
  bool _isLoaded = false;

  WeatherReport? _weather;
  bool _weatherLoading = false;
  String? _weatherError;

  bool get isLoaded => _isLoaded;
  String? get placeName => _name;

  /// Últimas coordenadas conocidas de la ubicación (o `null` si aún no se ha
  /// elegido ninguna). Las usa el selector de mapa para centrar la vista en el
  /// sitio actual en vez de en un punto por defecto.
  double? get latitude => _lat;
  double? get longitude => _lon;

  /// Etiqueta completa para la UI ("Madrid, Comunidad de Madrid, España"), o
  /// el nombre corto si no se guardó una, o `null` si no hay ubicación.
  String? get displayName => _displayName ?? _name;
  bool get hasLocation => _name != null && _name!.isNotEmpty;

  WeatherReport? get weather => _weather;
  bool get weatherLoading => _weatherLoading;
  String? get weatherError => _weatherError;

  Future<void> _init() async {
    await load();
    await refreshWeather();
  }

  /// Lee la ubicación persistida. No consulta el tiempo (eso es
  /// [refreshWeather]).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_nameKey)?.trim();
    _name = (name == null || name.isEmpty) ? null : name;
    _displayName = prefs.getString(_displayKey);
    _lat = prefs.getDouble(_latKey);
    _lon = prefs.getDouble(_lonKey);
    _isLoaded = true;
    notifyListeners();
  }

  /// Cambia la ubicación a la ciudad elegida en el autocompletado. Persiste
  /// nombre + coordenadas, **invalida la temperatura anterior de inmediato**
  /// (para que la UI no siga mostrando el dato viejo mientras llega el nuevo)
  /// y vuelve a consultar el tiempo con la nueva posición.
  Future<void> setPlace(PlaceResult place) async {
    _name = place.name;
    _displayName = place.displayName;
    _lat = place.latitude;
    _lon = place.longitude;
    _weather = null;
    _weatherError = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, place.name);
    await prefs.setString(_displayKey, place.displayName);
    await prefs.setDouble(_latKey, place.latitude);
    await prefs.setDouble(_lonKey, place.longitude);
    await prefs.setString(_cachedPlaceKey, place.name);

    await refreshWeather();
  }

  /// Vuelve a consultar el tiempo con la ubicación actual (o Madrid si aún no
  /// hay ninguna). Lo llama el botón "Actualizar" de la tarjeta de clima y
  /// [setPlace] tras un cambio de ciudad.
  Future<void> refreshWeather() async {
    _weatherLoading = true;
    _weatherError = null;
    notifyListeners();

    try {
      _weather = await _fetchWeather(
        latitude: _lat ?? WeatherService.defaultLatitude,
        longitude: _lon ?? WeatherService.defaultLongitude,
      );
      _weatherError = null;
    } catch (e) {
      _weatherError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _weatherLoading = false;
      notifyListeners();
    }
  }
}
