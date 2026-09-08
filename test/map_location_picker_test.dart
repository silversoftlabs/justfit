import 'dart:convert';

import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/services/place_search_service.dart';
import 'package:armario_virtual/services/spanish_municipalities_service.dart';
import 'package:armario_virtual/widgets/map_location_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// PNG transparente de 1x1: el `TileProvider` de los tests lo sirve para cada
/// tesela, así el mapa se monta sin tocar la red.
final _transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  '+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _FakeTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPixel);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
    // Calienta la caché del listado local ANTES de los `testWidgets`: dentro
    // del reloj falso de `testWidgets`, `rootBundle.loadString` no llega a
    // completarse; precargado aquí (async real), `nearest` resuelve desde
    // memoria en un microtask que `tester.pump()` sí vacía.
    await SpanishMunicipalitiesService.nearest(40.4168, -3.7038);
  });

  Future<PlaceResult?> pumpAndConfirm(
    WidgetTester tester, {
    required double lat,
    required double lon,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        locale: const Locale('es'),
        localizationsDelegates: _delegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SizedBox.shrink(),
      ),
    );

    PlaceResult? popped;
    navKey.currentState!
        .push<PlaceResult>(
          MaterialPageRoute(
            builder: (_) => MapLocationPicker(
              initialLatitude: lat,
              initialLongitude: lon,
              tileProvider: _FakeTileProvider(),
            ),
          ),
        )
        .then((value) => popped = value);
    await tester.pumpAndSettle();

    expect(find.text('Elige tu ubicación'), findsOneWidget);
    expect(find.text('© OpenStreetMap'), findsOneWidget);

    await tester.tap(find.text('Usar esta ubicación'));
    for (var i = 0; i < 20 && popped == null; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return popped;
  }

  testWidgets(
    'confirmar devuelve un PlaceResult con las coordenadas exactas del centro',
    (tester) async {
      final place =
          await pumpAndConfirm(tester, lat: 40.4168, lon: -3.7038);

      expect(place, isNotNull);
      // Sin mover el mapa, el centro sigue siendo el punto inicial.
      expect(place!.latitude, closeTo(40.4168, 0.0005));
      expect(place.longitude, closeTo(-3.7038, 0.0005));
      // El listado local reconoce el punto (geocodificación inversa de
      // respaldo, sin clave de WeatherAPI en tests) y le pone nombre, pero las
      // coordenadas siguen siendo las del punto, no las del municipio.
      expect(place.name, isNotEmpty);
      expect(place.displayName, contains('España'));
    },
  );

  testWidgets(
    'un punto en mar abierto se devuelve con las coordenadas como etiqueta',
    (tester) async {
      final place = await pumpAndConfirm(tester, lat: 30.0, lon: -40.0);

      expect(place, isNotNull);
      expect(place!.latitude, closeTo(30.0, 0.0005));
      expect(place.longitude, closeTo(-40.0, 0.0005));
      // Nadie reconoce el punto (sin clave de WeatherAPI en tests, sin
      // municipio cerca): la etiqueta son las propias coordenadas.
      expect(place.name, contains('30.0000'));
      expect(place.displayName, contains('-40.0000'));
    },
  );
}
