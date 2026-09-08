import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/providers/locale_provider.dart';
import 'package:armario_virtual/providers/location_provider.dart';
import 'package:armario_virtual/providers/outfit_history_provider.dart';
import 'package:armario_virtual/providers/wardrobe_provider.dart';
import 'package:armario_virtual/screens/daily_outfit_screen.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const testL10nDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void _l10nSetUp() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
  });
}

const _fastFail = Timeout(Duration(seconds: 30));

/// Monta `DailyOutfitScreen` sola, mismo patrón que
/// `outfit_screen_grid_test.dart`: `WardrobeProvider` real sobre
/// `SharedPreferences` (mock) y el tema con `AppPalette`, que la pantalla
/// necesita para sus tarjetas.
///
/// El clima llega de `LocationProvider`; aquí se monta con `autoLoad: false`
/// para que no dispare ninguna petición HTTP y `weather` se quede en `null`.
/// Los chips de "¿Quieres incluir algo específico?" y "Accesorios" no dependen
/// de que el tiempo cargue para renderizarse ni para responder a toques (solo
/// el botón "Generar Nuevo Outfit" se deshabilita mientras tanto), así que
/// esto no afecta a la interacción bajo test.
Future<void> _pumpDailyOutfitScreen(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});

  // Viewport alto (el tamaño de test por defecto es 800x600): la pantalla
  // completa (título + tarjeta de tiempo/error + chips de ocasión + sección
  // de outfit + chips de categoría/accesorios + botón) no cabe en 600 de
  // alto dentro del `ListView` scrollable, y los tests interactúan con chips
  // sin hacer scroll primero.
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WardrobeProvider()),
        ChangeNotifierProvider(create: (_) => OutfitHistoryProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider(autoLoad: false)),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        locale: const Locale('es'),
        localizationsDelegates: testL10nDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DailyOutfitScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// `selected` del `ChoiceChip` cuyo `label` es exactamente [text], entre
/// todos los `ChoiceChip` montados (`_CategoryOptionChip` construye uno
/// internamente por cada chip visible de esta pantalla).
bool _chipSelected(WidgetTester tester, String text) {
  final chip = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).firstWhere(
        (c) => (c.label as Text).data == text,
        orElse: () => throw StateError('No se encontró ningún ChoiceChip con label "$text"'),
      );
  return chip.selected;
}

void main() {
  _l10nSetUp();

  testWidgets(
    'activar "Accesorios" y marcar un sub-chip no desmarca la prenda '
    'principal fijada en "¿Quieres incluir algo específico?"',
    (tester) async {
      await _pumpDailyOutfitScreen(tester);

      // 1. Fija "Sudadera / Jersey" como prenda principal.
      await tester.tap(find.text('Sudadera / Jersey'));
      await tester.pump();

      expect(_chipSelected(tester, 'Sudadera / Jersey'), isTrue);

      // 2. Activa la sección de Accesorios (independiente de _lockedCategory).
      await tester.tap(find.text('Accesorios'));
      await tester.pump();

      expect(_chipSelected(tester, 'Accesorios'), isTrue);
      expect(
        _chipSelected(tester, 'Sudadera / Jersey'),
        isTrue,
        reason: 'Activar el toggle de Accesorios no debe desmarcar la prenda principal',
      );

      // 3. Marca un sub-chip de accesorio ("Reloj"), desplegado tras activar
      // el toggle.
      await tester.tap(find.text('Reloj'));
      await tester.pump();

      expect(_chipSelected(tester, 'Reloj'), isTrue);
      expect(
        _chipSelected(tester, 'Sudadera / Jersey'),
        isTrue,
        reason: 'Marcar un sub-chip de accesorio no debe desmarcar la prenda principal',
      );
      expect(
        _chipSelected(tester, 'Accesorios'),
        isTrue,
        reason: 'El toggle de Accesorios sigue activo tras marcar un sub-chip',
      );

      expect(tester.takeException(), isNull);
    },
    timeout: _fastFail,
  );

  testWidgets(
    'marcar dos sub-chips de Accesorios a la vez (selección múltiple) deja '
    'ambos seleccionados',
    (tester) async {
      await _pumpDailyOutfitScreen(tester);

      await tester.tap(find.text('Accesorios'));
      await tester.pump();

      await tester.tap(find.text('Reloj'));
      await tester.pump();
      await tester.tap(find.text('Collar / Cadena'));
      await tester.pump();

      expect(_chipSelected(tester, 'Reloj'), isTrue);
      expect(_chipSelected(tester, 'Collar / Cadena'), isTrue);

      expect(tester.takeException(), isNull);
    },
    timeout: _fastFail,
  );

  testWidgets(
    'desactivar el toggle de Accesorios oculta el grid de sub-chips',
    (tester) async {
      await _pumpDailyOutfitScreen(tester);

      await tester.tap(find.text('Accesorios'));
      await tester.pump();
      expect(find.text('Reloj'), findsOneWidget);

      await tester.tap(find.text('Accesorios'));
      await tester.pump();
      expect(find.text('Reloj'), findsNothing);

      expect(tester.takeException(), isNull);
    },
    timeout: _fastFail,
  );
}
