import 'package:armario_virtual/services/spanish_municipalities_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeForMatch', () {
    test('quita acentos, diéresis y apóstrofos, y pasa a minúsculas', () {
      expect(normalizeForMatch("L'Alcúdia"), 'lalcudia');
      expect(normalizeForMatch('Cádiz'), 'cadiz');
      expect(normalizeForMatch('IBI'), 'ibi');
    });
  });

  group('SpanishMunicipalitiesService.search', () {
    test('encuentra un municipio pequeño que WeatherAPI no resolvía bien (Ibi)', () async {
      final results = await SpanishMunicipalitiesService.search('Ibi');
      expect(results, isNotEmpty);
      final ibi = results.first;
      expect(ibi.name, 'Ibi');
      expect(ibi.displayName, contains('Alicante'));
      expect(ibi.latitude, closeTo(38.6253, 0.01));
      expect(ibi.longitude, closeTo(-0.5723, 0.01));
    });

    test('coincidencia exacta sale primero aunque haya "empieza por" más cortas', () async {
      final results = await SpanishMunicipalitiesService.search('Ibi');
      expect(results.first.name, 'Ibi');
    });

    test('ignora acentos y mayúsculas al comparar (alcudia -> L\'Alcúdia)', () async {
      final results = await SpanishMunicipalitiesService.search('alcudia');
      expect(results.map((r) => r.name), contains("L'Alcúdia"));
    });

    test('encuentra un municipio de varias palabras (Sant Boi de Llobregat)', () async {
      final results = await SpanishMunicipalitiesService.search('Sant Boi');
      expect(results.map((r) => r.name), contains('Sant Boi de Llobregat'));
    });

    test('devuelve como mucho maxResults coincidencias', () async {
      final results = await SpanishMunicipalitiesService.search('San');
      expect(results.length, lessThanOrEqualTo(SpanishMunicipalitiesService.maxResults));
    });

    test('consulta vacía o sin coincidencias devuelve lista vacía sin lanzar', () async {
      expect(await SpanishMunicipalitiesService.search(''), isEmpty);
      expect(await SpanishMunicipalitiesService.search('xyzxyzxyz-no-existe'), isEmpty);
    });
  });

  group('SpanishMunicipalitiesService.nearest', () {
    test('un punto sobre Madrid resuelve a un municipio conservando las coordenadas', () async {
      final place = await SpanishMunicipalitiesService.nearest(40.4168, -3.7038);
      expect(place, isNotNull);
      expect(place!.name, isNotEmpty);
      expect(place.displayName, contains('España'));
      // Se conservan las coordenadas EXACTAS del punto, no las del municipio.
      expect(place.latitude, 40.4168);
      expect(place.longitude, -3.7038);
    });

    test('un punto en medio del Atlántico no lo reclama ningún municipio', () async {
      final place = await SpanishMunicipalitiesService.nearest(30.0, -40.0);
      expect(place, isNull);
    });
  });
}
