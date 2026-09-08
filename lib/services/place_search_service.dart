import 'dart:convert';

import 'package:http/http.dart' as http;

import 'spanish_municipalities_service.dart';
import 'weather_service.dart' show WeatherApiConfig;

/// Una ciudad/localidad candidata del buscador de ubicaciones.
///
/// [name] es el nombre corto ("Madrid") que se persiste como
/// `onboarding_location` (compatible con lo que ya guardaba el onboarding);
/// [displayName] es la etiqueta completa para la UI ("Madrid, Comunidad de
/// Madrid, España").
class PlaceResult {
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;

  const PlaceResult({
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory PlaceResult.fromJson(Map<String, dynamic> json) => PlaceResult(
        name: json['name'] as String,
        displayName: json['displayName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is PlaceResult &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(latitude, longitude, displayName);

  @override
  String toString() => displayName;
}

/// Autocompletado de ciudades. Combina dos fuentes EN PARALELO:
///  - [SpanishMunicipalitiesService]: listado local (sin red) de municipios
///    españoles, con prioridad en el resultado — tapa el hueco de cobertura
///    de WeatherAPI en localidades pequeñas (ver su doc).
///  - El endpoint de búsqueda de WeatherAPI (`api.weatherapi.com/v1/search.json`,
///    la misma clave de API que ya usa [WeatherService] para resolver
///    coordenadas), que cubre el resto del mundo.
///
/// En ambos casos el resultado trae ya lat/lon resueltas: al elegir una
/// sugerencia, `LocationProvider.setPlace` consulta el tiempo directamente
/// con esas coordenadas (`WeatherService.fetchAt`), sin volver a geocodificar
/// — así que una localidad del listado local funciona igual de bien que una
/// de WeatherAPI para "Outfit del día", por pequeña que sea.
class PlaceSearchService {
  static const _timeout = Duration(seconds: 8);

  /// Al comparar un resultado local con uno de WeatherAPI para el mismo
  /// sitio, cuánta distancia (en grados, ~0.05° ≈ 5 km en el ecuador) se
  /// tolera antes de considerarlos "lugares distintos". Sobra para no
  /// duplicar una localidad que ambas fuentes encuentran, sin fundir dos
  /// pueblos vecinos de verdad distintos.
  static const _samePlaceToleranceDegrees = 0.05;

  /// Longitud mínima de la consulta para lanzar una búsqueda: por debajo de
  /// esto no se molesta en llamar a la API (evita ruido con 1 sola letra).
  static const minQueryLength = 2;

  /// Caracteres fuera de letras (con acentos/ñ), números, espacios, guiones y
  /// apóstrofos: puntuación suelta que el usuario puede teclear o pegar
  /// ("Ibi!?", "Ibi;") y que `search.json` no sabe interpretar.
  static final _stripSpecialChars = RegExp(r"[^\p{L}\p{N}\s'-]", unicode: true);
  static final _collapseSpaces = RegExp(r'\s+');

  /// Limpia la consulta libre del usuario antes de mandarla a WeatherAPI:
  ///  1. Se queda solo con el bloque ANTES de la primera coma — cuando el
  ///     usuario escribe "Ibi, Alicante" (nombre + provincia/región,
  ///     patrón habitual al copiar una sugerencia previa), mandar la cadena
  ///     completa hace que `search.json` ignore la localidad y busque por la
  ///     región/país en su lugar (p. ej. "Alicante" gana sobre "Ibi").
  ///     Quedarse solo con "Ibi" evita ESE problema concreto, aunque
  ///     `search.json` sigue siendo un autocompletado difuso con cobertura
  ///     limitada para localidades pequeñas — no hay combinación de query
  ///     client-side que garantice encontrarlas todas.
  ///  2. Quita cualquier carácter que no sea letra/número/espacio/guion/
  ///     apóstrofo, para que puntuación suelta no rompa la búsqueda. Los
  ///     espacios internos SÍ se conservan (y se colapsan a uno solo): un
  ///     nombre de varias palabras como "Palma de Mallorca" sigue intacto.
  static String _normalizeQuery(String query) {
    final beforeComma = query.split(',').first;
    final cleaned = beforeComma.replaceAll(_stripSpecialChars, '');
    return cleaned.trim().replaceAll(_collapseSpaces, ' ');
  }

  /// Busca localidades cuyo nombre coincide con [query] (ver [_normalizeQuery]
  /// para cómo se limpia antes de consultar). Lanza el listado local y
  /// WeatherAPI EN PARALELO (`Future.wait`) y antepone las coincidencias
  /// locales — ver el comentario de la clase. Devuelve lista vacía —nunca
  /// lanza— si la consulta normalizada es muy corta o ninguna de las dos
  /// fuentes encuentra nada: quien llama simplemente no enseña sugerencias.
  static Future<List<PlaceResult>> search(String query) async {
    final q = _normalizeQuery(query);
    if (q.length < minQueryLength) return const [];

    final results = await Future.wait([
      SpanishMunicipalitiesService.search(q),
      _searchWeatherApi(q),
    ]);
    final local = results[0];
    final remote = results[1];
    if (local.isEmpty) return remote;

    // Local primero; de WeatherAPI solo se añade lo que no sea (aprox.) el
    // mismo sitio que ya aportó el listado local, para no duplicar sugerencia.
    final merged = <PlaceResult>[...local];
    for (final place in remote) {
      final isDuplicate = local.any((l) => _isSamePlace(l, place));
      if (!isDuplicate) merged.add(place);
    }
    return merged;
  }

  /// Geocodificación INVERSA: dado un punto (lat/lon) elegido en el mapa,
  /// devuelve la localidad conocida más cercana con su nombre y etiqueta ya
  /// resueltos, para no guardar una ubicación "sin nombre". Combina las dos
  /// mismas fuentes que [search]:
  ///  - [SpanishMunicipalitiesService.nearest]: municipio español más cercano
  ///    dentro de un radio corto (sin red).
  ///  - El endpoint `search.json` de WeatherAPI admite `q=lat,lon` y responde
  ///    con la localidad más próxima.
  ///
  /// Devuelve `null` si ninguna fuente reconoce el punto (mar abierto, zona sin
  /// cobertura, o sin clave de API / sin conexión): quien llama construye
  /// entonces un [PlaceResult] con las coordenadas como etiqueta. Nunca lanza.
  static Future<PlaceResult?> reverseGeocode(double lat, double lon) async {
    final results = await Future.wait([
      _reverseGeocodeWeatherApi(lat, lon),
      SpanishMunicipalitiesService.nearest(lat, lon),
    ]);
    // Aquí manda WeatherAPI (al revés que [search]): su geocodificación
    // inversa devuelve la ciudad/población que contiene el punto, mientras que
    // el listado local solo sabe dar el municipio con el centroide más
    // cercano — útil solo como respaldo cuando no hay clave o conexión.
    return results[0] ?? results[1];
  }

  static Future<PlaceResult?> _reverseGeocodeWeatherApi(
    double lat,
    double lon,
  ) async {
    if (WeatherApiConfig.apiKey.isEmpty) return null;

    final uri = Uri.https('api.weatherapi.com', '/v1/search.json', {
      'key': WeatherApiConfig.apiKey,
      'q': '$lat,$lon',
      'lang': 'es',
    });

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body);
      if (results is! List || results.isEmpty) return null;

      final m = results.first as Map<String, dynamic>;
      final name = (m['name'] as String?)?.trim();
      // El nombre lo aporta la respuesta; las coordenadas se conservan tal cual
      // las eligió el usuario en el mapa (no las del centro de la localidad).
      if (name == null || name.isEmpty) return null;

      final region = (m['region'] as String?)?.trim();
      final country = (m['country'] as String?)?.trim();
      final parts = <String>[
        name,
        if (region != null && region.isNotEmpty && region != name) region,
        if (country != null && country.isNotEmpty) country,
      ];

      return PlaceResult(
        name: name,
        displayName: parts.join(', '),
        latitude: lat,
        longitude: lon,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isSamePlace(PlaceResult a, PlaceResult b) {
    return (a.latitude - b.latitude).abs() < _samePlaceToleranceDegrees &&
        (a.longitude - b.longitude).abs() < _samePlaceToleranceDegrees;
  }

  /// Solo la mitad "WeatherAPI" de [search]. Nunca lanza —lista vacía si no
  /// hay clave de API, no hay conexión, la respuesta no es válida o no hay
  /// coincidencias— para que un fallo de red no tumbe el listado local, que
  /// [search] siempre puede mostrar igualmente.
  static Future<List<PlaceResult>> _searchWeatherApi(String q) async {
    if (WeatherApiConfig.apiKey.isEmpty) return const [];

    final uri = Uri.https('api.weatherapi.com', '/v1/search.json', {
      'key': WeatherApiConfig.apiKey,
      'q': q,
      // Nombres de localidad devueltos (y coincidencias) en español.
      'lang': 'es',
    });

    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final results = jsonDecode(response.body);
      if (results is! List) return const [];

      final places = <PlaceResult>[];
      for (final raw in results) {
        final m = raw as Map<String, dynamic>;
        final name = (m['name'] as String?)?.trim();
        final lat = (m['lat'] as num?)?.toDouble();
        final lon = (m['lon'] as num?)?.toDouble();
        if (name == null || name.isEmpty || lat == null || lon == null) continue;

        final region = (m['region'] as String?)?.trim();
        final country = (m['country'] as String?)?.trim();
        final parts = <String>[
          name,
          if (region != null && region.isNotEmpty && region != name) region,
          if (country != null && country.isNotEmpty) country,
        ];

        places.add(
          PlaceResult(
            name: name,
            displayName: parts.join(', '),
            latitude: lat,
            longitude: lon,
          ),
        );
      }
      return places;
    } catch (_) {
      return const [];
    }
  }
}
