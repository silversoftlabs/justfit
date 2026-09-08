import 'package:armario_virtual/models/outfit_filters.dart';
import 'package:armario_virtual/providers/location_provider.dart';
import 'package:armario_virtual/services/place_search_service.dart';
import 'package:armario_virtual/services/weather_service.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeatherReport _report(double celsius) => WeatherReport(
      temperatureCelsius: celsius,
      descriptionKey: 'weather_clear',
      icon: Icons.wb_sunny,
      condition: celsius >= 18 ? WeatherCondition.calor : WeatherCondition.frio,
    );

const _madrid = PlaceResult(
    name: 'Madrid', displayName: 'Madrid, España', latitude: 40.4, longitude: -3.7);
const _oslo = PlaceResult(
    name: 'Oslo', displayName: 'Oslo, Noruega', latitude: 59.9, longitude: 10.7);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setPlace persiste la ciudad y consulta el tiempo con SUS coordenadas', () async {
    final calls = <(double, double)>[];
    final provider = LocationProvider(
      autoLoad: false,
      weatherFetcher: ({required latitude, required longitude}) async {
        calls.add((latitude, longitude));
        return _report(latitude > 50 ? 1 : 26);
      },
    );

    await provider.setPlace(_madrid);
    expect(provider.placeName, 'Madrid');
    expect(provider.displayName, 'Madrid, España');
    expect(provider.hasLocation, isTrue);
    expect(provider.weather?.temperatureCelsius, 26);
    expect(calls.last, (40.4, -3.7));

    await provider.setPlace(_oslo);
    expect(provider.weather?.temperatureCelsius, 1);
    expect(calls.last, (59.9, 10.7));

    // Un provider nuevo sobre las mismas prefs recupera la última ubicación.
    final reloaded = LocationProvider(autoLoad: false);
    await reloaded.load();
    expect(reloaded.placeName, 'Oslo');
    expect(reloaded.displayName, 'Oslo, Noruega');
  });

  test('al cambiar de ciudad no se queda con la temperatura anterior si falla la red', () async {
    var failNext = false;
    final provider = LocationProvider(
      autoLoad: false,
      weatherFetcher: ({required latitude, required longitude}) async {
        if (failNext) throw Exception('sin conexión');
        return _report(20);
      },
    );

    await provider.setPlace(_madrid);
    expect(provider.weather?.temperatureCelsius, 20);

    failNext = true;
    await provider.setPlace(_oslo);
    expect(provider.weather, isNull, reason: 'la temperatura vieja de Madrid se invalida');
    expect(provider.weatherError, isNotNull);
  });

  test('refreshWeather sin ubicación usa las coordenadas por defecto (Madrid)', () async {
    (double, double)? used;
    final provider = LocationProvider(
      autoLoad: false,
      weatherFetcher: ({required latitude, required longitude}) async {
        used = (latitude, longitude);
        return _report(14);
      },
    );

    await provider.refreshWeather();
    expect(used, (WeatherService.defaultLatitude, WeatherService.defaultLongitude));
    expect(provider.weather?.temperatureCelsius, 14);
  });

  test('notifica a los oyentes al cambiar de ubicación', () async {
    final provider = LocationProvider(
      autoLoad: false,
      weatherFetcher: ({required latitude, required longitude}) async => _report(18),
    );
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.setPlace(_madrid);

    expect(notifications, greaterThan(0));
  });
}
