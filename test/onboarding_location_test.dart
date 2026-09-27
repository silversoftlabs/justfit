import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/providers/locale_provider.dart';
import 'package:armario_virtual/providers/location_provider.dart';
import 'package:armario_virtual/screens/onboarding_screen.dart';
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

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  String? language,
  VoidCallback? onFinished,
}) async {
  SharedPreferences.setMockInitialValues(
    language == null ? {} : {LocaleProvider.storageKey: language},
  );
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LocationProvider(autoLoad: false)),
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(initialLanguageCode: language),
        ),
      ],
      child: Consumer<LocaleProvider>(
        builder: (context, locale, child) => MaterialApp(
          // La app es "dark first" y el onboarding hereda ese tema.
          theme: ThemeData(brightness: Brightness.dark),
          locale: locale.locale,
          localizationsDelegates: _delegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OnboardingScreen(onFinished: onFinished ?? () {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double? _currentPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller?.page;

FilledButton _continueButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
  });

  testWidgets(
    'el nombre es obligatorio: "Continuar" con el campo vacío muestra el error '
    'y no avanza',
    (tester) async {
      await _pumpOnboarding(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      expect(find.text('Escribe tu nombre para continuar.'), findsNothing);

      // Vacío (y solo espacios) → error y sigue en el slide del nombre.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      expect(find.text('Escribe tu nombre para continuar.'), findsOneWidget);

      // Al escribir un nombre el error desaparece y se puede avanzar.
      await tester.enterText(find.byType(TextField), 'Lucía');
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu nombre para continuar.'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 2);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'la ciudad solo se elige en el mapa: sin campo de texto y "Continuar" '
    'desactivado hasta elegir una',
    (tester) async {
      await _pumpOnboarding(tester);

      // Slide 0 (idioma): "Continuar" está habilitado (hay idioma por defecto).
      expect(_continueButton(tester, 'Continuar').onPressed, isNotNull);

      // Slide 1 (nombre) y, con nombre, slide 2 (ciudad).
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Lucía');
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('¿En qué ciudad estás?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('onboarding-map-button')),
        findsOneWidget,
      );
      expect(find.textContaining('Elige tu ciudad en el mapa'), findsOneWidget);

      // ...y "Continuar" queda deshabilitado mientras no haya ciudad elegida.
      expect(
        _continueButton(tester, 'Continuar').onPressed,
        isNull,
        reason: 'sin ciudad seleccionada no se puede pasar de este slide',
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sin nombre ni ciudad: arrastrar hacia delante devuelve al primer slide '
    'obligatorio; hacia atrás sí navega',
    (tester) async {
      await _pumpOnboarding(tester);
      expect(_currentPage(tester), 0);

      // Avanza al slide 1 (nombre) con el botón.
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);

      // Fling hacia delante sin nombre: termina devuelto y 100 % alineado al
      // slide del nombre, con el error visible.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
      expect(
        _currentPage(tester),
        1,
        reason: 'sin nombre no se puede pasar del slide del nombre',
      );
      expect(find.text('Escribe tu nombre para continuar.'), findsOneWidget);

      // Con nombre pero sin ciudad, el límite pasa a ser el slide de ubicación.
      await tester.enterText(find.byType(TextField), 'Lucía');
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 2);
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
      expect(
        _currentPage(tester),
        2,
        reason: 'sin ciudad no se puede pasar del slide de ubicación',
      );
      expect(_continueButton(tester, 'Continuar').onPressed, isNull);

      // Hacia atrás sí se puede volver hasta el slide de idioma.
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 0);
      expect(find.text('Elige tu idioma'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '«Saltar» sin nombre o sin ciudad lleva a ese slide en vez de terminar',
    (tester) async {
      var finished = false;
      await _pumpOnboarding(tester, onFinished: () => finished = true);

      // En el slide 0 el botón "Saltar" está activo.
      final skip = find.widgetWithText(TextButton, 'Saltar');
      expect(tester.widget<TextButton>(skip).onPressed, isNotNull);

      await tester.tap(skip);
      await tester.pumpAndSettle();

      expect(finished, isFalse, reason: 'no se puede saltar el onboarding sin nombre');
      expect(_currentPage(tester), 1);
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);

      // Y en el propio slide del nombre, "Saltar" queda desactivado.
      expect(tester.widget<TextButton>(skip).onPressed, isNull);

      // Con nombre, "Saltar" lleva al slide de la ciudad y allí se desactiva.
      await tester.enterText(find.byType(TextField), 'Lucía');
      await tester.pumpAndSettle();
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(finished, isFalse, reason: 'no se puede saltar el onboarding sin ciudad');
      expect(_currentPage(tester), 2);
      expect(tester.widget<TextButton>(skip).onPressed, isNull);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('el nombre escrito se persiste en `user_name` al teclear',
      (tester) async {
    await _pumpOnboarding(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Lucía');
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_name'), 'Lucía');
  });

  testWidgets(
    'el selector de idioma del slide 1 cambia el Locale de toda la app en vivo',
    (tester) async {
      await _pumpOnboarding(tester);

      // Arranca en español.
      expect(find.text('Elige tu idioma'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continuar'), findsOneWidget);

      // Toca "English": la pantalla se reconstruye ya en inglés.
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(find.text('Choose your language'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(find.text('Elige tu idioma'), findsNothing);
    },
  );

  testWidgets('arranca en inglés si app_language == "en"', (tester) async {
    await _pumpOnboarding(tester, language: 'en');
    expect(find.text('Choose your language'), findsOneWidget);
    expect(find.text('Elige tu idioma'), findsNothing);
  });
}
