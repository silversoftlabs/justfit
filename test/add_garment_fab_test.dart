import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/providers/favorite_outfits_provider.dart';
import 'package:armario_virtual/providers/locale_provider.dart';
import 'package:armario_virtual/providers/wardrobe_provider.dart';
import 'package:armario_virtual/screens/home_screen.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:armario_virtual/theme/ios_design.dart';
import 'package:armario_virtual/widgets/pressable_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alto de la barra de navegación de `MainNavigation` (tema: 66).
const double _navBarHeight = 66;

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

  _transitionTests();

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
            // Dentro de un Scaffold exterior, como en `MainNavigation`: ahí es
            // donde `ScaffoldMessenger` pinta la notificación, a la altura del FAB.
            home: const Scaffold(
              extendBody: true,
              bottomNavigationBar: SizedBox(height: _navBarHeight),
              body: HomeScreen(),
            ),
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
        find
            .ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(PressableScale),
            )
            .first,
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

  testWidgets(
    'el FAB se vuelve a expandir al cerrarse la notificación, pero no si otra '
    'la sustituye',
    (tester) async {
      await _pumpHomeWithGarments(tester, ['a', 'b', 'c']);

      Rect fabRect() => tester.getRect(
            find
                .ancestor(
                  of: find.byIcon(Icons.add),
                  matching: find.byType(PressableScale),
                )
                .first,
          );

      final expandedWidth = fabRect().width;
      expect(expandedWidth, greaterThan(56));
      expect(find.text('Añadir prenda'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(fabRect().width, 56);
      expect(find.text('Añadir prenda'), findsNothing);

      // Segunda notificación que sustituye a la primera: el cierre de la
      // primera NO debe expandir el FAB mientras la segunda sigue visible.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      // Varios fotogramas: la salida de la primera, su `closed` y una
      // eventual (incorrecta) animación de expansión necesitan cada uno el suyo.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Prenda eliminada'), findsOneWidget);
      expect(fabRect().width, 56);

      // Cuando la vigente se cierra por su duración, vuelve a expandirse.
      // En pasos cortos: el temporizador de 3 s arranca al terminar la
      // animación de entrada, que necesita sus propios fotogramas.
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Prenda eliminada'), findsNothing);
      expect(fabRect().width, expandedWidth);
      expect(find.text('Añadir prenda'), findsOneWidget);
    },
  );

  testWidgets(
    'el FAB flota por encima de la barra de navegación y, replegado, queda '
    'junto a la notificación sin solaparse',
    (tester) async {
      await _pumpHomeWithGarments(tester, ['a', 'b']);
      const screenHeight = 1600.0;

      Rect fabRect() => tester.getRect(
            find
                .ancestor(
                  of: find.byIcon(Icons.add),
                  matching: find.byType(PressableScale),
                )
                .first,
          );

      expect(
        fabRect().bottom,
        lessThanOrEqualTo(screenHeight - _navBarHeight - 16),
        reason: 'el FAB no puede quedar bajo la barra de navegación',
      );

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final fab = fabRect();
      final pill = tester.getRect(
        find
            .ancestor(
              of: find.text('Prenda eliminada'),
              matching: find.byType(GlassCard),
            )
            .first,
      );
      expect(pill.overlaps(fab), isFalse, reason: 'píldora y FAB no se tocan');
      expect(pill.right, lessThan(fab.left));
      expect(
        (pill.center.dy - fab.center.dy).abs(),
        lessThan(1),
        reason: 'misma fila: centros alineados verticalmente',
      );
      expect(pill.bottom, lessThanOrEqualTo(screenHeight - _navBarHeight));

      await tester.pumpWidget(const SizedBox());
    },
  );
}

void _transitionTests() {
  testWidgets(
    'al cambiar a una categoría vacía y volver, el FAB se desvanece y reaparece '
    'suavemente, sin la rotación por defecto del Scaffold',
    (tester) async {
      // Todas las prendas de prueba son camisetas (Parte superior), así que
      // "Parte inferior" queda vacía.
      await _pumpHomeWithGarments(tester, ['a', 'b']);

      // Por clave (y aunque esté fuera de escena): `Icons.add` también está
      // en el botón de la tarjeta vacía, que se funde al mismo tiempo.
      final fab = find.byKey(HomeScreen.addGarmentFabKey, skipOffstage: false);
      double fabOpacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: fab,
                  matching: find.byType(FadeTransition, skipOffstage: false),
                )
                .first,
          )
          .opacity
          .value;
      void expectNoRotation() {
        for (final r in tester.widgetList<RotationTransition>(
          find.ancestor(
            of: fab,
            matching: find.byType(RotationTransition, skipOffstage: false),
          ),
        )) {
          // En reposo el Scaffold deja `turns` en 1.0 (vuelta completa = sin giro).
          expect(r.turns.value % 1, 0, reason: 'el FAB no debe girar');
        }
      }

      expect(fabOpacity(), 1);

      await tester.tap(find.text('Parte inferior'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(fabOpacity(), inExclusiveRange(0, 1), reason: 'salida gradual');
      expectNoRotation();

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No hay prendas en esta categoría'), findsOneWidget);
      // Oculto del todo: solo queda el "+" de la tarjeta vacía.
      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(find.text('Todos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(fabOpacity(), inExclusiveRange(0, 1), reason: 'entrada gradual');
      expectNoRotation();

      await tester.pump(const Duration(milliseconds: 400));
      expect(fabOpacity(), 1);
      expect(find.text('No hay prendas en esta categoría'), findsNothing);
    },
  );
}

Future<void> _pumpHomeWithGarments(WidgetTester tester, List<String> ids) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final wardrobe = WardrobeProvider();
  var guard = 0;
  while (wardrobe.isLoading && guard++ < 1000) {
    await tester.pump(const Duration(milliseconds: 5));
  }
  for (final id in ids) {
    await wardrobe.addGarment(_garment(id));
  }

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
        // Dentro de un Scaffold exterior, como en `MainNavigation`: ahí es
            // donde `ScaffoldMessenger` pinta la notificación, a la altura del FAB.
            home: const Scaffold(
              extendBody: true,
              bottomNavigationBar: SizedBox(height: _navBarHeight),
              body: HomeScreen(),
            ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
