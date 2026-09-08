import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'place_search_service.dart' show PlaceResult;

/// Quita acentos/diéresis/apóstrofos y pasa a minúsculas, para comparar
/// nombres de localidad sin importar cómo los escriba el usuario ("alcudia"
/// debe encontrar "L'Alcúdia", "cadiz" debe encontrar "Cádiz").
String normalizeForMatch(String value) {
  var out = value.toLowerCase();
  for (final entry in _diacritics.entries) {
    out = out.replaceAll(entry.key, entry.value);
  }
  return out;
}

const _diacritics = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
  "'": '', '´': '', '`': '',
};

/// Una localidad del listado local, ya con su forma normalizada
/// precalculada (se compara en cada tecla que escribe el usuario, así que no
/// merece la pena rehacerla en cada búsqueda).
class _Municipio {
  final String name;
  final String province;
  final double lat;
  final double lon;
  final String normalized;

  _Municipio({required this.name, required this.province, required this.lat, required this.lon})
      : normalized = normalizeForMatch(name);

  factory _Municipio.fromJson(Map<String, dynamic> json) => _Municipio(
        name: json['n'] as String,
        province: json['p'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );

  PlaceResult toPlaceResult() => PlaceResult(
        name: name,
        displayName: province.isEmpty ? '$name, España' : '$name, $province, España',
        latitude: lat,
        longitude: lon,
      );
}

/// Búsqueda LOCAL (sin red) de localidades españolas, para tapar el hueco de
/// cobertura del buscador difuso de WeatherAPI (`search.json`, ver
/// [PlaceSearchService]) en municipios pequeños o medianos: p. ej. "Ibi",
/// "Sant Boi de Llobregat" o "L'Alcúdia" no aparecían o daban coincidencias
/// erróneas de otros países.
///
/// Los datos (`assets/data/es_municipios.json`, ~8.500 localidades, ~525 KB)
/// vienen del volcado público de GeoNames.org (https://www.geonames.org,
/// licencia CC BY 4.0 — el crédito de atribución está en el footer de
/// `ProfileSheet`, junto al de WeatherAPI). Generados con
/// `tools/generar_es_municipios.py`; ver ese script para el criterio exacto
/// de qué localidades entran.
class SpanishMunicipalitiesService {
  /// Cuántas coincidencias locales se devuelven como máximo por búsqueda.
  /// [PlaceSearchService.search] las antepone a las de WeatherAPI.
  static const maxResults = 5;

  static List<_Municipio>? _cache;
  static Future<List<_Municipio>>? _loading;

  /// Carga y cachea el asset la primera vez; las búsquedas siguientes lo
  /// reutilizan en memoria (nunca vuelve a tocar disco). Un fallo de carga
  /// (asset ausente, JSON corrupto) se recuerda como lista vacía en vez de
  /// reintentar en cada tecla.
  static Future<List<_Municipio>> _load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _loadFromAsset();
  }

  static Future<List<_Municipio>> _loadFromAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/data/es_municipios.json');
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = decoded
          .map((e) => _Municipio.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      _cache = list;
      return list;
    } catch (_) {
      const empty = <_Municipio>[];
      _cache = empty;
      return empty;
    }
  }

  /// Busca localidades cuyo nombre (sin acentos, en minúsculas) empieza por o
  /// contiene [query]. [query] debe llegar ya limpio de comas/símbolos (ver
  /// `PlaceSearchService._normalizeQuery`) — aquí solo se normalizan acentos
  /// y mayúsculas para la comparación. Nunca lanza.
  ///
  /// Orden de relevancia: coincidencia exacta primero, luego "empieza por"
  /// (alfabético), luego "contiene en cualquier posición" (alfabético) —
  /// para que escribir "Ibi" no entierre la propia "Ibi" bajo otro municipio
  /// que solo la contenga como subcadena.
  static Future<List<PlaceResult>> search(String query) async {
    final needle = normalizeForMatch(query);
    if (needle.isEmpty) return const [];

    final municipios = await _load();
    if (municipios.isEmpty) return const [];

    _Municipio? exact;
    final startsWith = <_Municipio>[];
    final contains = <_Municipio>[];
    for (final m in municipios) {
      if (m.normalized == needle) {
        exact ??= m;
      } else if (m.normalized.startsWith(needle)) {
        startsWith.add(m);
      } else if (m.normalized.contains(needle)) {
        contains.add(m);
      }
    }
    startsWith.sort((a, b) => a.normalized.compareTo(b.normalized));
    contains.sort((a, b) => a.normalized.compareTo(b.normalized));

    final ordered = [?exact, ...startsWith, ...contains];
    return ordered.take(maxResults).map((m) => m.toPlaceResult()).toList();
  }

  /// Radio máximo (en grados, ~0,35° ≈ 35 km) para dar por buena la
  /// coincidencia de [nearest]: más allá, el punto elegido en el mapa cae
  /// entre municipios del listado y es mejor devolver `null` y dejar que lo
  /// resuelva WeatherAPI (o las coordenadas a secas) que colgarle el nombre de
  /// un pueblo lejano.
  static const _nearestToleranceDegrees = 0.35;

  /// Municipio español más cercano al punto ([lat], [lon]) elegido en el mapa,
  /// dentro de [_nearestToleranceDegrees]. El [PlaceResult] devuelto conserva
  /// **las coordenadas exactas del punto** (no las del centro del municipio):
  /// solo se toma prestado el nombre/etiqueta para no guardar una ubicación
  /// anónima. Devuelve `null` si no hay ningún municipio lo bastante cerca o el
  /// listado no cargó. Nunca lanza.
  static Future<PlaceResult?> nearest(double lat, double lon) async {
    final municipios = await _load();
    if (municipios.isEmpty) return null;

    _Municipio? best;
    var bestSq = double.infinity;
    for (final m in municipios) {
      final dLat = m.lat - lat;
      // Corrige la longitud por la latitud para que la distancia sea real y no
      // se "alargue" cerca de los polos (en España el factor es ~0,75).
      final dLon = (m.lon - lon) * math.cos(lat * math.pi / 180);
      final sq = dLat * dLat + dLon * dLon;
      if (sq < bestSq) {
        bestSq = sq;
        best = m;
      }
    }

    if (best == null || math.sqrt(bestSq) > _nearestToleranceDegrees) {
      return null;
    }

    final label = best.toPlaceResult();
    return PlaceResult(
      name: label.name,
      displayName: label.displayName,
      latitude: lat,
      longitude: lon,
    );
  }
}
