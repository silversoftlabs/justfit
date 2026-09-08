import 'package:armario_virtual/services/place_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaceResult', () {
    test('roundtrip JSON conserva todos los campos', () {
      const place = PlaceResult(
        name: 'Madrid',
        displayName: 'Madrid, Comunidad de Madrid, España',
        latitude: 40.4168,
        longitude: -3.7038,
      );

      final back = PlaceResult.fromJson(place.toJson());

      expect(back, place);
      expect(back.name, 'Madrid');
      expect(back.displayName, 'Madrid, Comunidad de Madrid, España');
      expect(back.latitude, 40.4168);
      expect(back.longitude, -3.7038);
    });

    test('iguala por coordenadas + etiqueta (no por el nombre corto)', () {
      const a = PlaceResult(
          name: 'Madrid', displayName: 'Madrid, España', latitude: 40.4, longitude: -3.7);
      const b = PlaceResult(
          name: 'MADRID', displayName: 'Madrid, España', latitude: 40.4, longitude: -3.7);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('PlaceSearchService.search', () {
    test('devuelve lista vacía para consultas demasiado cortas sin tocar la red', () async {
      expect(await PlaceSearchService.search(''), isEmpty);
      expect(await PlaceSearchService.search('a'), isEmpty);
      expect(await PlaceSearchService.search('  '), isEmpty);
    });

    test(
      'la normalización (comas y caracteres especiales) también cuenta para la '
      'longitud mínima, sin tocar la red',
      () async {
        // Todo lo que queda ANTES de la coma es más corto que minQueryLength.
        expect(await PlaceSearchService.search('a, Alicante'), isEmpty);
        // Solo puntuación: no queda nada tras limpiar caracteres especiales.
        expect(await PlaceSearchService.search('¡¡!!'), isEmpty);
        expect(await PlaceSearchService.search(','), isEmpty);
      },
    );

    test(
      'un municipio pequeño con provincia pegada por coma se resuelve vía el '
      'listado local (WeatherAPI sin clave en los tests no aporta nada)',
      () async {
        final results = await PlaceSearchService.search('Ibi, Alicante');
        expect(results, isNotEmpty);
        expect(results.first.name, 'Ibi');
      },
    );
  });
}
