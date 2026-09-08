import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/providers/favorite_outfits_provider.dart';
import 'package:armario_virtual/providers/locale_provider.dart';
import 'package:armario_virtual/providers/wardrobe_provider.dart';
import 'package:armario_virtual/screens/home_screen.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class _PushSpy extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Garment _garment(String id) => Garment(
      id: id,
      imagePath: '$id.png',
      category: GarmentCategory.camiseta,
      color: 'Negro',
      style: GarmentStyle.casual,
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
  });

  testWidgets(
    'el FAB "Añadir ropa" replegado por una notificación sigue abriendo Añadir ropa',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final wardrobe = WardrobeProvider();
      var guard = 0;
      while (wardrobe.isLoading && guard++ < 1000) {
        await tester.pump(const Duration(milliseconds: 5));
      }
      await wardrobe.addGarment(_garment('a'));
      await wardrobe.addGarment(_garment('b'));

      final spy = _PushSpy();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WardrobeProvider>.value(value: wardrobe),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider(create: (_) => FavoriteOutfitsProvider()),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppPalette.light]),
            locale: const Locale('es'),
            localizationsDelegates: _delegates,
            supportedLocales: AppLocalizations.supportedLocales,
            navigatorObservers: [spy],
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Borra una prenda: aparece la notificación y el FAB se repliega a icono.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // notificación + repliegue

      // La notificación está visible (es lo que repliega el FAB).
      expect(find.text('Prenda eliminada'), findsOneWidget);

      final inkRect = tester.getRect(
        find.ancestor(of: find.byIcon(Icons.add), matching: find.byType(InkWell)).first,
      );
      expect(inkRect.width, 56, reason: 'el FAB replegado es un cuadrado de icono');

      // Tocar el borde del botón replegado (no el pixel exacto del icono) — el
      // punto que ANTES quedaba muerto por el desbordamiento del `Row`.
      final before = spy.pushes;
      await tester.tapAt(inkRect.centerLeft + const Offset(6, 0));
      await tester.pump();

      expect(
        spy.pushes,
        greaterThan(before),
        reason: 'todo el FAB replegado debe ser pulsable, no solo el icono',
      );

      // Desmonta el árbol para descartar la ruta pendiente y los timers de la
      // notificación sin llegar a construir AddGarmentScreen.
      await tester.pumpWidget(const SizedBox());
    },
  );
}
