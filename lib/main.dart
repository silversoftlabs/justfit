import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'providers/favorite_outfits_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/location_provider.dart';
import 'providers/outfit_history_provider.dart';
import 'providers/outfit_plan_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'providers/user_profile_provider.dart';
import 'providers/wardrobe_provider.dart';
import 'providers/wardrobe_settings_provider.dart';
import 'screens/daily_outfit_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_palette.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initCrashReporting();
  // La pantalla de Onboarding solo se muestra si aún no se ha completado.
  // Se lee aquí, antes de `runApp`, para no provocar un parpadeo entre la
  // navegación principal y el onboarding en el primer frame.
  final prefs = await SharedPreferences.getInstance();
  final showOnboarding = !(prefs.getBool('hasCompletedOnboarding') ?? false);
  // Idioma persistido (`app_language`): se lee aquí, antes de `runApp`, para
  // arrancar ya en el idioma correcto sin un parpadeo en el primer frame.
  final languageCode = prefs.getString(LocaleProvider.storageKey);
  runApp(ArmarioVirtualApp(
    showOnboarding: showOnboarding,
    initialLanguageCode: languageCode,
  ));
}

/// Inicializa Firebase y engancha Crashlytics a los tres canales de error:
/// el del framework de Flutter (`FlutterError.onError`), el de errores
/// asíncronos ajenos a Flutter (`PlatformDispatcher.instance.onError`) y los
/// `recordError` manuales.
///
/// Si Firebase todavía no está configurado (falta `flutterfire configure`) o
/// no hay red en el arranque, se captura la excepción y la app sigue
/// funcionando sin reporte de fallos.
Future<void> _initCrashReporting() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final crashlytics = FirebaseCrashlytics.instance;
    // En debug no se envían informes (evita ruido durante el desarrollo).
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (error, stack) {
    debugPrint('Crashlytics no inicializado: $error\n$stack');
  }
}

/// Paleta "Minimalista Moderno / Warm Minimalist": fondo arena, superficies
/// en lino y un único acento en verde salvia. Los tonos base viven en
/// [AppColors] (`theme/app_palette.dart`), fuente única de verdad.
class _Palette {
  static const background = AppColors.background;
  static const surface = AppColors.surface;
  static const sage = AppColors.primary;
  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;

  // Borde sutil sobre fondos cálidos (arena/lino), sin recurrir a grises fríos.
  static const line = Color(0xFFE4DCCB);

  // Variante clara del salvia para que el acento siga siendo legible como
  // `primary` (fondo) en modo oscuro, donde el tono base sería demasiado
  // apagado sobre `nightBg`.
  static const sageSoft = Color(0xFFA8C2AE);

  // Acento secundario (terracota cálida), deliberadamente distinto del
  // salvia: se usa para resaltar selección/foco y para el color de aviso
  // (p.ej. "falta un campo obligatorio" en add_garment_screen.dart). Si
  // `secondary` fuera igual a `primary` esas dos señales -completado vs.
  // pendiente- se volverían indistinguibles.
  static const clay = Color(0xFFC17F59);
  static const claySoft = Color(0xFFD9A47F);

  static const nightBg = Color(0xFF121212);
  static const nightSurface = Color(0xFF1E1E1E);
  static const nightSurfaceAlt = Color(0xFF262626);
  static const nightBorder = Color(0xFF333333);

  // Mismos valores que `AppPalette.dark.strongText`/`textSecondary` (ver
  // `theme/app_palette.dart`): ≥15:1 y ≥6:1 de contraste respectivamente
  // sobre `nightBg`/`nightSurface`/`nightSurfaceAlt`.
  static const nightTextPrimary = Color(0xFFF9F8F6);
  static const nightTextSecondary = Color(0xFFA0AEC0);
}

class ArmarioVirtualApp extends StatelessWidget {
  /// Si `true`, la ruta inicial es la `OnboardingScreen` en vez de
  /// `MainNavigation`. Lo decide `main()` a partir de SharedPreferences;
  /// por defecto `false` (p. ej. en tests que montan la app directamente).
  final bool showOnboarding;

  /// Código de idioma (`'es'`/`'en'`) leído de `app_language` por `main()`.
  /// `null` en el primer arranque o en tests → español por defecto.
  final String? initialLanguageCode;

  const ArmarioVirtualApp({
    super.key,
    this.showOnboarding = false,
    this.initialLanguageCode,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WardrobeProvider()),
        ChangeNotifierProvider(create: (_) => WardrobeSettingsProvider()),
        ChangeNotifierProvider(create: (_) => OutfitPlanProvider()),
        ChangeNotifierProvider(create: (_) => FavoriteOutfitsProvider()),
        ChangeNotifierProvider(create: (_) => OutfitHistoryProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(initialLanguageCode: initialLanguageCode),
        ),
      ],
      child: _App(showOnboarding: showOnboarding),
    );
  }
}

class _App extends StatelessWidget {
  final bool showOnboarding;

  const _App({this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeModeProvider>().themeMode;
    final locale = context.watch<LocaleProvider>().locale;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).t('app_title'),
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildTheme(
        const ColorScheme.light(
          brightness: Brightness.light,
          primary: _Palette.sage,
          onPrimary: Colors.white,
          secondary: _Palette.clay,
          onSecondary: _Palette.textPrimary,
          surface: _Palette.surface,
          onSurface: _Palette.textPrimary,
          onSurfaceVariant: _Palette.textSecondary,
          surfaceContainerHighest: _Palette.surface,
          outline: _Palette.line,
          outlineVariant: _Palette.line,
          error: Color(0xFFB3261E),
          onError: Colors.white,
        ),
        scaffoldBackground: _Palette.background,
      ),
      darkTheme: _buildTheme(
        const ColorScheme.dark(
          brightness: Brightness.dark,
          primary: _Palette.sageSoft,
          onPrimary: _Palette.nightBg,
          secondary: _Palette.claySoft,
          onSecondary: _Palette.nightBg,
          surface: _Palette.nightSurface,
          onSurface: _Palette.nightTextPrimary,
          onSurfaceVariant: _Palette.nightTextSecondary,
          surfaceContainerHighest: _Palette.nightSurfaceAlt,
          outline: _Palette.nightBorder,
          outlineVariant: _Palette.nightBorder,
          error: Color(0xFFF2B8B5),
          onError: Color(0xFF601410),
        ),
        scaffoldBackground: _Palette.nightBg,
      ),
      home: showOnboarding ? const _OnboardingGate() : const MainNavigation(),
    );
  }
}

/// Envuelve la `OnboardingScreen` y, cuando esta termina, la sustituye por
/// `MainNavigation` sin salir de la ruta raíz (evita dejar el onboarding en
/// la pila de navegación).
class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? const MainNavigation()
          : OnboardingScreen(onFinished: () => setState(() => _done = true)),
    );
  }
}

ThemeData _buildTheme(ColorScheme scheme, {required Color scaffoldBackground}) {
  final isDark = scheme.brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffoldBackground,
    splashFactory: InkSparkle.splashFactory,
    textTheme: ThemeData(brightness: scheme.brightness).textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface)
        .copyWith(
          titleLarge: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: scheme.onSurface,
          ),
          titleSmall: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            color: scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffoldBackground,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? _Palette.nightSurface : Colors.white,
      selectedColor: scheme.primary,
      // `WidgetStateColor` (en vez de un `Color` fijo): un chip seleccionado
      // cambia su fondo a `scheme.primary`, así que su texto tiene que pasar
      // a `onPrimary` para seguir siendo legible sobre ese fondo — con un
      // color estático aquí, `ChoiceChip`/`FilterChip` seleccionados quedan
      // con el texto de `onSurface` (pensado para el fondo neutro de la
      // tarjeta) sobre `scheme.primary`, lo que en modo oscuro es texto casi
      // blanco sobre verde salvia claro: ~1.8:1 de contraste, muy por debajo
      // del mínimo AA (4.5:1).
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface,
        ),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      secondaryLabelStyle: TextStyle(
        color: scheme.onPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      side: BorderSide(color: scheme.outlineVariant),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurfaceVariant,
        selectedBackgroundColor: scheme.primary,
        selectedForegroundColor: Colors.white,
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? _Palette.nightSurface : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.secondary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondary.withValues(alpha: isDark ? 0.28 : 0.22),
      elevation: 0,
      height: 66,
      // Iconos inactivos en `onSurfaceVariant` (en vez del color por
      // defecto de Material) para garantizar contraste AA legible sobre el
      // fondo de la barra en ambos modos.
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: scheme.onSurface,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    extensions: [isDark ? AppPalette.dark : AppPalette.light],
  );
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  /// Pestañas ya visitadas al menos una vez: solo esas construyen su
  /// pantalla real dentro del `IndexedStack` de abajo (las demás quedan como
  /// un hueco vacío) para no pagar su coste de arranque hasta que el usuario
  /// las abre. `IndexedStack` mantiene TODOS sus hijos montados a la vez
  /// (para no perder su estado al cambiar de pestaña) — con las dos
  /// pantallas reales desde el primer frame, abrir la app ya construía
  /// `DailyOutfitScreen` entera, que en su propio `initState` dispara una
  /// llamada de red (`WeatherService.fetchToday`) y genera un outfit, antes
  /// incluso de que el usuario vea nada, mucho antes de tocar esa pestaña.
  final _visitedIndices = {0};

  Widget _buildTab(int index) {
    if (!_visitedIndices.contains(index)) return const SizedBox.shrink();
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const DailyOutfitScreen();
      case 2:
        return const FavoritesScreen();
      default:
        throw StateError('Índice de pestaña desconocido: $index');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [for (var i = 0; i < 3; i++) _buildTab(i)],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() {
            _currentIndex = index;
            _visitedIndices.add(index);
          }),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.checkroom_outlined),
              selectedIcon: const Icon(Icons.checkroom),
              label: t.t('nav_wardrobe'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.wb_sunny_outlined),
              selectedIcon: const Icon(Icons.wb_sunny),
              label: t.t('nav_daily_outfit'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.favorite_border),
              selectedIcon: const Icon(Icons.favorite),
              label: t.t('nav_favorites'),
            ),
          ],
        ),
      ),
    );
  }
}
