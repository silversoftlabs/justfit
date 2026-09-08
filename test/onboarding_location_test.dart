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
    'la ubicación es obligatoria: "Continuar" se desactiva en el slide de ciudad '
    'hasta elegir una',
    (tester) async {
      await _pumpOnboarding(tester);

      // Slide 0 (idioma): "Continuar" está habilitado (hay idioma por defecto).
      expect(_continueButton(tester, 'Continuar').onPressed, isNotNull);

      // Avanza al slide 1 (nombre + ciudad).
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();

      // Estamos en el slide de "Sobre ti".
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('onboarding-city-autocomplete')),
        findsOneWidget,
      );
      expect(find.textContaining('Elige tu ciudad'), findsOneWidget);

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
    'sin ciudad: arrastrar hacia delante devuelve al slide de ubicación; '
    'hacia atrás sí navega',
    (tester) async {
      await _pumpOnboarding(tester);
      expect(_currentPage(tester), 0);

      // Avanza al slide 1 (nombre + ciudad) con el botón.
      await tester.tap(find.widgetWithText(FilledButton, 'Continuar'));
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 1);
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);

      // Fling hacia delante sin ciudad: el PageView puede llegar a moverse,
      // pero termina devuelto y 100 % alineado al slide de ubicación.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
      await tester.pumpAndSettle();
      expect(
        _currentPage(tester),
        1,
        reason: 'sin ciudad no se puede pasar del slide de ubicación',
      );
      expect(_continueButton(tester, 'Continuar').onPressed, isNull);

      // Hacia atrás sí se puede volver al slide de idioma.
      await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
      await tester.pumpAndSettle();
      expect(_currentPage(tester), 0);
      expect(find.text('Elige tu idioma'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '«Saltar» sin ciudad válida lleva al slide de ubicación en vez de terminar',
    (tester) async {
      var finished = false;
      await _pumpOnboarding(tester, onFinished: () => finished = true);

      // En el slide 0 el botón "Saltar" está activo.
      final skip = find.widgetWithText(TextButton, 'Saltar');
      expect(tester.widget<TextButton>(skip).onPressed, isNotNull);

      await tester.tap(skip);
      await tester.pumpAndSettle();

      expect(finished, isFalse, reason: 'no se puede saltar el onboarding sin ciudad');
      expect(_currentPage(tester), 1);
      expect(find.text('¡Hola! ¿Cómo te llamas?'), findsOneWidget);

      // Y en el propio slide de ubicación, "Saltar" queda desactivado.
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
