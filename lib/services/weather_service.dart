import 'dart:convert';

import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/outfit_filters.dart';

/// Clave de API de WeatherAPI.com (https://www.weatherapi.com/my/): el plan
/// Free permite hasta 1 millón de llamadas al mes. Se lee de una variable de
/// entorno de compilación para no commitear la clave en el repositorio.
///
/// En local vive en `dart_define.json` (raíz del repo, ignorado por git —
/// ver `.gitignore`), con la forma `{"WEATHER_API_KEY": "tu_clave"}`.
/// `.vscode/launch.json` ya pasa `--dart-define-from-file=dart_define.json`
/// en sus configuraciones de Debug/Profile/Release, y
/// `flutter build appbundle --release --dart-define-from-file=dart_define.json`
/// hace lo mismo desde línea de comandos (ver `PUBLICAR_EN_PLAY.md`); en
/// CI/CD, genera ese mismo archivo (o usa `--dart-define=WEATHER_API_KEY=...`
/// directamente) a partir de un secreto del pipeline, nunca hardcodeado aquí.
/// [WeatherService] lanza la clave i18n `weather_err_missing_api_key` si
/// llega vacía.
class WeatherApiConfig {
  static const String apiKey = String.fromEnvironment('WEATHER_API_KEY');
}

/// Lectura del tiempo actual, ya traducida a lo que necesita la pantalla
/// "Outfit del día": temperatura y descripción para mostrar, y [condition]
/// para alimentar `OutfitRecommendationService.generate` con el mismo filtro
/// de clima que ya usan los chips manuales de la pantalla de Outfits.
class WeatherReport {
  final double temperatureCelsius;

  /// Clave i18n de la descripción del cielo (p. ej. `weather_clear`). La
  /// pantalla la resuelve con `AppLocalizations.t(...)`: el servicio no tiene
  /// `BuildContext` y no debe fabricar texto visible.
  final String descriptionKey;

  final IconData icon;
  final WeatherCondition condition;

  const WeatherReport({
    required this.temperatureCelsius,
    required this.descriptionKey,
    required this.icon,
    required this.condition,
  });
}

/// Consulta el tiempo actual en WeatherAPI.com (https://www.weatherapi.com):
/// requiere una clave de API gratuita (ver [WeatherApiConfig]). 100%
/// on-line, sin caché del pronóstico — cada llamada a [fetchToday] es una
/// petición nueva. El uso de este servicio debe mostrar en algún lugar
/// visible de la app el crédito "Powered by WeatherAPI.com" (ver el footer
/// de `ProfileSheet`), tal y como exigen sus condiciones de uso.
///
/// La ubicación la elige el usuario en el onboarding (clave
/// `onboarding_location` de SharedPreferences, p. ej. "Madrid", "Barcelona").
/// Ese texto se geocodifica a coordenadas con el endpoint de búsqueda de
/// WeatherAPI y el resultado se cachea para no repetir la búsqueda en cada
/// consulta. Si el campo está vacío o la geocodificación falla, se usa la
/// última ubicación resuelta y, en su defecto, Madrid como valor por defecto.
class WeatherService {
  /// Ciudad por defecto (Madrid) cuando no hay ninguna ubicación indicada por
  /// el usuario ni ninguna resuelta anteriormente. Pública para que
  /// `LocationProvider` la use como respaldo cuando aún no hay coordenadas.
  static const defaultLatitude = 40.4168;
  static const defaultLongitude = -3.7038;

  /// Ciudad escrita por el usuario en el onboarding.
  static const _locationPrefKey = 'onboarding_location';

  /// Caché de la última ubicación resuelta a coordenadas.
  static const _cachedPlaceKey = 'weather_cached_place';
  static const _cachedLatKey = 'weather_cached_lat';
  static const _cachedLonKey = 'weather_cached_lon';

  static const _timeout = Duration(seconds: 10);

  static const _host = 'api.weatherapi.com';

  /// Tiempo actual resolviendo la ubicación desde SharedPreferences (ver
  /// [_resolveCoordinates]). Se mantiene por compatibilidad; `LocationProvider`
  /// prefiere [fetchAt] con coordenadas ya conocidas.
  static Future<WeatherReport> fetchToday() async {
    final (latitude, longitude) = await _resolveCoordinates();
    return fetchAt(latitude: latitude, longitude: longitude);
  }

  /// Tiempo actual en unas coordenadas concretas. Lo usa `LocationProvider`
  /// tras un cambio de ubicación: ya tiene la lat/lon exacta de la ciudad
  /// elegida en el autocompletado, sin necesidad de volver a geocodificar.
  static Future<WeatherReport> fetchAt({
    required double latitude,
    required double longitude,
  }) async {
    if (WeatherApiConfig.apiKey.isEmpty) {
      // El mensaje es una CLAVE i18n: `LocationProvider` la guarda tal cual y
      // la pantalla la resuelve con `AppLocalizations`.
      throw Exception('weather_err_missing_api_key');
    }

    final uri = Uri.https(_host, '/v1/current.json', {
      'key': WeatherApiConfig.apiKey,
      'q': '$latitude,$longitude',
    });

    final http.Response response;
    try {
      response = await http.get(uri).timeout(_timeout);
    } catch (_) {
      throw Exception('weather_err_connection');
    }

    if (response.statusCode != 200) {
      throw Exception('weather_err_bad_response');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('weather_err_unexpected');
    }

    final current = body['current'] as Map<String, dynamic>?;
    final temperature = (current?['temp_c'] as num?)?.toDouble();
    final condition = current?['condition'] as Map<String, dynamic>?;
    final weatherCode = (condition?['code'] as num?)?.toInt();
    if (temperature == null || weatherCode == null) {
      throw Exception('weather_err_incomplete');
    }

    final (descriptionKey, icon, isRainy) = _describeWeatherCode(weatherCode);
    return WeatherReport(
      temperatureCelsius: temperature,
      descriptionKey: descriptionKey,
      icon: icon,
      condition: _conditionFor(temperature, isRainy),
    );
  }

  /// Decide con qué coordenadas se consulta el tiempo:
  ///  1. Campo vacío -> última ubicación resuelta o, en su defecto, Madrid.
  ///  2. Misma ciudad que la última resuelta -> se reutiliza su caché (no se
  ///     vuelve a geocodificar).
  ///  3. Ciudad nueva -> se geocodifica y el resultado se cachea.
  ///  4. La geocodificación falla -> última ubicación resuelta o Madrid.
  static Future<(double, double)> _resolveCoordinates() async {
    final prefs = await SharedPreferences.getInstance();
    final place = prefs.getString(_locationPrefKey)?.trim() ?? '';
    final cachedPlace = prefs.getString(_cachedPlaceKey);
    final cachedLat = prefs.getDouble(_cachedLatKey);
    final cachedLon = prefs.getDouble(_cachedLonKey);
    final (double, double)? cached = (cachedLat != null && cachedLon != null)
        ? (cachedLat, cachedLon)
        : null;

    if (place.isEmpty) {
      return cached ?? (defaultLatitude, defaultLongitude);
    }

    if (cached != null &&
        cachedPlace != null &&
        cachedPlace.toLowerCase() == place.toLowerCase()) {
      return cached;
    }

    final geocoded = await _geocode(place);
    if (geocoded != null) {
      await prefs.setString(_cachedPlaceKey, place);
      await prefs.setDouble(_cachedLatKey, geocoded.$1);
      await prefs.setDouble(_cachedLonKey, geocoded.$2);
      return geocoded;
    }

    return cached ?? (defaultLatitude, defaultLongitude);
  }

  /// Traduce un nombre de ciudad/país a coordenadas con el endpoint de
  /// búsqueda de WeatherAPI (`/v1/search.json`, el mismo que usa el
  /// autocompletado de `PlaceSearchService`). Devuelve `null` si no hay
  /// clave de API, no hay conexión, la respuesta no es válida o no hay
  /// ninguna coincidencia (el llamador decide el respaldo).
  static Future<(double, double)?> _geocode(String place) async {
    if (WeatherApiConfig.apiKey.isEmpty) return null;

    final uri = Uri.https(_host, '/v1/search.json', {
      'key': WeatherApiConfig.apiKey,
      'q': place,
    });

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body);
      if (results is! List || results.isEmpty) return null;
      final first = results.first as Map<String, dynamic>;
      final lat = (first['lat'] as num?)?.toDouble();
      final lon = (first['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return (lat, lon);
    } catch (_) {
      return null;
    }
  }

  /// [WeatherCondition] solo tiene tres valores (calor/frío/lluvia): la
  /// lluvia manda sobre la temperatura, ya que un día lluvioso pide otra
  /// ropa aunque haga calor. Si no llueve, se decide por un umbral simple de
  /// temperatura — el enum no tiene un valor intermedio ("templado").
  static WeatherCondition _conditionFor(double temperatureCelsius, bool isRainy) {
    if (isRainy) return WeatherCondition.lluvia;
    return temperatureCelsius >= 18 ? WeatherCondition.calor : WeatherCondition.frio;
  }

  /// Traduce el código de condición que devuelve WeatherAPI (tabla completa
  /// en https://www.weatherapi.com/docs/weather_conditions.json) a una CLAVE
  /// i18n de descripción, un icono, y si implica lluvia o nieve (para
  /// [_conditionFor]).
  static (String, IconData, bool) _describeWeatherCode(int code) {
    switch (code) {
      case 1000:
        return ('weather_clear', Icons.wb_sunny_outlined, false);
      case 1003:
        return ('weather_partlyCloudy', Icons.wb_cloudy_outlined, false);
      case 1006:
      case 1009:
        return ('weather_cloudy', Icons.cloud_outlined, false);
      case 1030:
      case 1135:
      case 1147:
        return ('weather_fog', Icons.blur_on, false);
      case 1063:
      case 1072:
      case 1150:
      case 1153:
      case 1168:
      case 1171:
      case 1180:
      case 1183:
      case 1186:
      case 1189:
      case 1192:
      case 1195:
      case 1198:
      case 1201:
      case 1240:
      case 1243:
      case 1246:
        return ('weather_rain', Icons.water_drop_outlined, true);
      case 1066:
      case 1069:
      case 1114:
      case 1117:
      case 1204:
      case 1207:
      case 1210:
      case 1213:
      case 1216:
      case 1219:
      case 1222:
      case 1225:
      case 1237:
      case 1249:
      case 1252:
      case 1255:
      case 1258:
      case 1261:
      case 1264:
      case 1279:
      case 1282:
        return ('weather_snow', Icons.ac_unit_outlined, true);
      case 1087:
      case 1273:
      case 1276:
        return ('weather_storm', Icons.flash_on, true);
      default:
        return ('weather_variable', Icons.wb_cloudy_outlined, false);
    }
  }
}
