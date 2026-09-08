import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/location_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/map_location_picker.dart';

/// Pantalla de bienvenida que se muestra una única vez, antes de entrar a la
/// app. Cuatro slides deslizables (idioma, nombre + ubicación para el clima,
/// cómo organizar el armario y bienvenida) con indicador de páginas y botón
/// "Saltar". Persistencia:
///
///  - El idioma se aplica y guarda EN VIVO al tocar la tarjeta del slide 1
///    (`LocaleProvider.setLanguage` → clave `app_language`).
///  - La ciudad la guarda `LocationProvider.setPlace` (nombre + coordenadas).
///  - Al terminar: `hasCompletedOnboarding = true` y `user_name` (si no vacío).
///
/// Va en modo oscuro (la app es "dark first"): fondo #1A1A1A, contenedores
/// #242424, texto claro y acento dorado #CBA75D. Los colores están fijados
/// aquí, no leídos del `ColorScheme` global, para conservar la identidad
/// dorada de la bienvenida independientemente del tema de la app.
class OnboardingScreen extends StatefulWidget {
  /// Se invoca cuando el usuario termina ("Empezar") o pulsa "Saltar", una
  /// vez guardadas las preferencias. `main.dart` lo usa para intercambiar
  /// esta pantalla por la navegación principal.
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// --- Paleta del onboarding (modo oscuro) ----------------------------------
const _bg = Color(0xFF1A1A1A); // fondo de pantalla
const _card = Color(0xFF242424); // tarjetas de selección, campos de texto
const _ink = Color(0xFFF5F3EF); // texto principal (blanco cálido, ~13:1 sobre _card)
const _inkSoft = Color(0xFFB3ADA3); // texto secundario / iconos (~6:1 sobre _card)
const _gold = Color(0xFFCBA75D); // acento (sin cambios)
const _line = Color(0xFF3C3A36); // bordes sutiles de tarjeta/campo
const _danger = Color(0xFFF2B8B5); // aviso "falta la ciudad" legible sobre _bg

const _pageCount = 4;

/// Índice del slide "Sobre ti" (nombre + ciudad). Es donde la ubicación es
/// obligatoria: sin una ciudad elegida de las sugerencias no se puede pasar
/// de aquí (ver el botón inferior en `_OnboardingScreenState.build`).
const _locationPageIndex = 1;

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  int _page = 0;
  late String _language = context.read<LocaleProvider>().languageCode;
  bool _saving = false;

  /// Ciudad elegida en el autocompletado. Obligatoria para pasar del slide
  /// [_locationPageIndex]; `null` hasta que el usuario toca una sugerencia.
  PlaceResult? _selectedPlace;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// `onPageChanged` del `PageView`. La ubicación es obligatoria: si el usuario
  /// consigue arrastrar (fling, arrastre largo…) más allá del slide
  /// [_locationPageIndex] sin una ciudad válida, se le devuelve a ese slide con
  /// una animación en el frame siguiente. Así el gesto en curso termina de
  /// forma natural y la vista queda 100 % alineada, en vez de congelar el
  /// `PageController` a medio camino cambiando la física en mitad del arrastre.
  void _onPageChanged(int page) {
    if (page > _locationPageIndex && _selectedPlace == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goToPage(_locationPageIndex);
      });
      return;
    }
    setState(() => _page = page);
  }

  /// "Saltar" no puede saltarse el paso de ciudad: sin una ubicación válida
  /// lleva al usuario al slide de ubicación en vez de terminar el onboarding.
  void _onSkip() {
    if (_selectedPlace == null) {
      _goToPage(_locationPageIndex);
      return;
    }
    _finish();
  }

  /// Persiste el nombre en `SharedPreferences` (clave `user_name`) en cuanto el
  /// usuario escribe, para no depender solo de que llegue a pulsar "Continuar".
  Future<void> _persistName(String value) async {
    final name = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (name.isEmpty) {
      await prefs.remove('user_name');
    } else {
      await prefs.setString('user_name', name);
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    FocusManager.instance.primaryFocus?.unfocus();

    final location = context.read<LocationProvider>();
    // El idioma ya se aplicó y persistió al tocar la tarjeta (ver `onSelect`);
    // se reafirma aquí por si el usuario nunca la tocó y luego cambia algo.
    await context.read<LocaleProvider>().setLanguage(_language);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCompletedOnboarding', true);
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await prefs.setString('user_name', name);
      // Terminar el onboarding con un nombre lo hace el válido: se descarta un
      // `profile_name` anterior para que el `ProfileSheet` muestre este.
      await prefs.remove('profile_name');
    }

    // La ciudad la guarda `LocationProvider.setPlace` (nombre + coordenadas) y,
    // de paso, dispara la primera consulta del tiempo con esa ubicación. No se
    // espera a que el tiempo llegue: "Empezar" entra a la app de inmediato y
    // `DailyOutfitScreen` recoge la temperatura en cuanto el provider la tiene.
    // `place` puede ser `null` si se llegó aquí por "Saltar" sin elegir ciudad.
    final place = _selectedPlace;
    if (place != null) {
      unawaited(location.setPlace(place));
    }

    if (!mounted) return;
    widget.onFinished();
  }

  void _selectLanguage(String code) {
    setState(() => _language = code);
    // Cambia el Locale de TODA la app en el acto (y lo persiste).
    context.read<LocaleProvider>().setLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isLast = _page == _pageCount - 1;
    final locationRequired = _page == _locationPageIndex && _selectedPlace == null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Fondo oscuro → iconos de la barra de estado en claro.
      value: SystemUiOverlayStyle.light
          .copyWith(statusBarColor: Colors.transparent),
      child: Theme(
        // Hereda el tema (oscuro por defecto) de la app y solo fuerza el
        // cursor dorado, para conservar el acento de la bienvenida en los
        // campos de texto sin volver a fijar un modo claro/oscuro propio.
        data: Theme.of(context).copyWith(
          textSelectionTheme: const TextSelectionThemeData(cursorColor: _gold),
        ),
        child: Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: Column(
              children: [
                // "Saltar" se oculta en el slide de ubicación mientras falte la
                // ciudad; en los demás sin ciudad, al pulsarlo lleva a ese paso.
                _TopBar(showSkip: !isLast && !locationRequired, onSkip: _onSkip),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    // Física por defecto de la plataforma: no se toca en mitad
                    // del gesto. El bloqueo del paso de ubicación se hace en
                    // `_onPageChanged` devolviendo al slide correcto.
                    onPageChanged: _onPageChanged,
                    children: [
                      _LanguageSlide(
                        selected: _language,
                        onSelect: _selectLanguage,
                      ),
                      _AboutYouSlide(
                        nameController: _nameController,
                        selectedPlace: _selectedPlace,
                        showLocationHint: locationRequired,
                        onNameChanged: _persistName,
                        onPlaceSelected: (place) =>
                            setState(() => _selectedPlace = place),
                      ),
                      const _OrganizationSlide(),
                      const _WelcomeSlide(),
                    ],
                  ),
                ),
                _PageIndicator(count: _pageCount, current: _page),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        // Texto oscuro sobre el dorado: ~8:1 de contraste
                        // (el blanco de antes quedaba en ~2:1).
                        foregroundColor: const Color(0xFF241E10),
                        disabledBackgroundColor: _gold.withValues(alpha: 0.30),
                        disabledForegroundColor:
                            const Color(0xFF241E10).withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      onPressed: _saving || locationRequired
                          ? null
                          : isLast
                              ? _finish
                              : () => _goToPage(_page + 1),
                      child: Text(
                        isLast ? t.t('common_start') : t.t('common_continue'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Barra superior con "Saltar" -----------------------------------------
class _TopBar extends StatelessWidget {
  final bool showSkip;
  final VoidCallback onSkip;

  const _TopBar({required this.showSkip, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          opacity: showSkip ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: showSkip ? onSkip : null,
              style: TextButton.styleFrom(foregroundColor: _inkSoft),
              child: Text(
                AppLocalizations.of(context).t('common_skip'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Indicador de páginas ----------------------------------------------------
class _PageIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _PageIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 8,
          width: active ? 24 : 8,
          decoration: BoxDecoration(
            color: active ? _gold : _gold.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

// --- Estructura común de un slide ------------------------------------------
class _SlideShell extends StatelessWidget {
  final IconData? icon;
  final Widget? header;
  final String title;
  final String subtitle;
  final Widget child;

  const _SlideShell({
    this.icon,
    this.header,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          if (header != null)
            Center(child: header!)
          else if (icon != null)
            Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(
                  color: Color(0x26CBA75D), // _gold @ ~15% (halo sutil sobre _bg)
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: _gold),
              ),
            ),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: _ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: _inkSoft, height: 1.45),
          ),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }
}

// --- Slide 1: idioma -------------------------------------------------------
class _LanguageSlide extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _LanguageSlide({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SlideShell(
      icon: Icons.translate,
      title: t.t('onb_lang_title'),
      subtitle: t.t('onb_lang_subtitle'),
      child: Column(
        children: [
          _ChoiceCard(
            emoji: '🇪🇸',
            label: t.t('onb_lang_spanish'),
            selected: selected == 'es',
            onTap: () => onSelect('es'),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            emoji: '🇬🇧',
            label: t.t('onb_lang_english'),
            selected: selected == 'en',
            onTap: () => onSelect('en'),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _gold : _line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? _gold : _inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Slide 2: nombre + ubicación para el tiempo -------------------------
class _AboutYouSlide extends StatelessWidget {
  final TextEditingController nameController;
  final PlaceResult? selectedPlace;
  final bool showLocationHint;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<PlaceResult> onPlaceSelected;

  const _AboutYouSlide({
    required this.nameController,
    required this.selectedPlace,
    required this.showLocationHint,
    required this.onNameChanged,
    required this.onPlaceSelected,
  });

  /// Abre el mapa interactivo para elegir la ubicación tocando un pin. El
  /// [PlaceResult] resultante trae lat/lon ya resueltas: cuenta igual que
  /// elegir una sugerencia del buscador para desbloquear el slide.
  Future<void> _pickOnMap(BuildContext context) async {
    final place = await MapLocationPicker.show(
      context,
      initialLatitude: selectedPlace?.latitude,
      initialLongitude: selectedPlace?.longitude,
    );
    if (place != null) onPlaceSelected(place);
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkSoft),
        prefixIcon: const Icon(Icons.search, color: _inkSoft),
        filled: true,
        fillColor: _card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: _line),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: _gold, width: 1.6),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SlideShell(
      icon: Icons.waving_hand_outlined,
      title: t.t('onb_about_title'),
      subtitle: t.t('onb_about_subtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OnbTextField(
            controller: nameController,
            hintText: t.t('onb_your_name'),
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            onChanged: onNameChanged,
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              t.t('onb_city_label'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _inkSoft,
              ),
            ),
          ),
          CityAutocompleteField(
            key: const ValueKey('onboarding-city-autocomplete'),
            initialValue: selectedPlace,
            decoration: _fieldDecoration(t.t('onb_city_hint')),
            onSelected: onPlaceSelected,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _pickOnMap(context),
            icon: const Icon(Icons.map_outlined, color: _gold),
            label: Text(t.t('map_select_on_map')),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              backgroundColor: _card,
              side: const BorderSide(color: _line),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (selectedPlace != null)
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: _gold),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.t('onb_city_selected', {'city': selectedPlace!.displayName}),
                    style: const TextStyle(
                        fontSize: 13, color: _ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Icon(
                  showLocationHint ? Icons.error_outline : Icons.info_outline,
                  size: 16,
                  color: showLocationHint ? _danger : _inkSoft,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.t('onb_city_required'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: showLocationHint ? _danger : _inkSoft,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Campo de texto con el estilo del onboarding (tarjeta blanca, borde dorado
/// al enfocar).
class _OnbTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;

  const _OnbTextField({
    required this.controller,
    required this.hintText,
    required this.icon,
    required this.textInputAction,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textCapitalization: TextCapitalization.words,
      textInputAction: textInputAction,
      style: const TextStyle(color: _ink, fontSize: 16),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: _inkSoft),
        prefixIcon: Icon(icon, color: _inkSoft),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _gold, width: 1.6),
        ),
      ),
    );
  }
}

// --- Slide 3: organización del armario -----------------------------------
class _OrganizationSlide extends StatelessWidget {
  const _OrganizationSlide();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SlideShell(
      icon: Icons.checkroom_outlined,
      title: t.t('onb_org_title'),
      subtitle: t.t('onb_org_subtitle'),
      child: Column(
        children: [
          _Step(
            icon: Icons.add_a_photo_outlined,
            title: t.t('onb_org_step1_title'),
            text: t.t('onb_org_step1_text'),
          ),
          const SizedBox(height: 14),
          _Step(
            icon: Icons.category_outlined,
            title: t.t('onb_org_step2_title'),
            text: t.t('onb_org_step2_text'),
          ),
          const SizedBox(height: 14),
          _Step(
            icon: Icons.favorite_border,
            title: t.t('onb_org_step3_title'),
            text: t.t('onb_org_step3_text'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Step({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x26CBA75D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _gold, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Slide 4: bienvenida JUSTFIT ----------------------------------------
class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return _SlideShell(
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Image(
            image: AssetImage('assets/branding/justfit_emblem.png'),
            width: 116,
            height: 116,
          ),
          SizedBox(height: 16),
          Text(
            'JUSTFIT',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: _ink,
            ),
          ),
        ],
      ),
      title: t.t('onb_welcome_title'),
      subtitle: t.t('onb_welcome_subtitle'),
      child: const SizedBox.shrink(),
    );
  }
}
