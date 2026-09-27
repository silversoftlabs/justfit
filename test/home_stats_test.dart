import 'package:armario_virtual/l10n/app_localizations.dart';
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

const _fastFail = Timeout(Duration(seconds: 30));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
  });

  testWidgets(
    'el contador de la Home cuenta los outfits guardados y se actualiza en '
    'tiempo real al añadir uno a favoritos',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final favorites = FavoriteOutfitsProvider();
      var guard = 0;
      while (favorites.isLoading && guard++ < 1000) {
        await tester.pump(const Duration(milliseconds: 5));
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => WardrobeProvider()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()),
            ChangeNotifierProvider<FavoriteOutfitsProvider>.value(
              value: favorites,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: const [AppPalette.light]),
            locale: const Locale('es'),
            localizationsDelegates: _delegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Cifra mostrada en la tarjeta cuya etiqueta es "Outfits guardados".
      Finder outfitsValue(String value) => find.descendant(
            of: find.ancestor(
              of: find.text('Outfits guardados'),
              matching: find.byType(Column),
            ).first,
            matching: find.text(value),
          );

      expect(outfitsValue('0'), findsOneWidget);
      expect(find.textContaining('Outfits creados'), findsNothing);

      await favorites.addFavoriteOutfit(garmentIds: ['a', 'b'], tags: const []);
      await tester.pump();

      expect(outfitsValue('1'), findsOneWidget);

      await favorites.removeFavoriteOutfit(favorites.favorites.single.id);
      await tester.pump();

      expect(outfitsValue('0'), findsOneWidget);
    },
    timeout: _fastFail,
  );
}
