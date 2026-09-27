import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/favorite_outfits_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/location_provider.dart';
import '../providers/theme_mode_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/city_autocomplete_field.dart';
import '../widgets/map_location_picker.dart';
import '../widgets/pressable_scale.dart';
import 'wardrobe_settings_screen.dart';
import '../theme/ios_design.dart';

/// Bottom sheet de "Perfil y Configuración", abierto al tocar el avatar del
/// header en `home_screen.dart`.
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  static Future<void> show(BuildContext context) {
    HapticFeedback.lightImpact();
    return showGlassSheet(
      context: context,
      isScrollControlled: true,
      wrap: false,
      builder: (_) => const ProfileSheet(),
    );
  }

  /// Abre un buscador de ciudad con autocompletado. Al elegir una,
  /// `LocationProvider.setPlace` persiste la nueva ubicación e invalida la
  /// temperatura anterior, que se vuelve a consultar de inmediato: la tarjeta
  /// del tiempo de "Outfit del día" y el outfit se refrescan solos.
  Future<void> _editLocation(BuildContext context) async {
    HapticFeedback.selectionClick();
    final location = context.read<LocationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final t = AppLocalizations.of(context);

    final picked = await showGlassSheet<PlaceResult>(
      context: context,
      isScrollControlled: true,
      wrap: false,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: _LocationPickerSheet(
          current: location.displayName,
          currentLatitude: location.latitude,
          currentLongitude: location.longitude,
        ),
      ),
    );

    if (picked == null) return;
    // No se espera al `fetch` del tiempo: la tarjeta de "Outfit del día" ya
    // muestra su estado de carga y se actualiza sola vía el provider.
    unawaited(location.setPlace(picked));
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.t('profile_updating_weather', {'city': picked.name})),
      ),
    );
  }

  /// Selector de idioma: cambia el `Locale` de toda la app al instante (vía
  /// [LocaleProvider], que reconstruye `MaterialApp`) y persiste la elección.
  Future<void> _editLanguage(BuildContext context) async {
    HapticFeedback.selectionClick();
    final localeProvider = context.read<LocaleProvider>();
    final code = await showGlassSheet<String>(
      context: context,
      wrap: false,
      builder: (_) => _LanguagePickerSheet(current: localeProvider.languageCode),
    );
    if (code != null) await localeProvider.setLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    final wardrobe = context.watch<WardrobeProvider>();
    final favorites = context.watch<FavoriteOutfitsProvider>();
    final themeModeProvider = context.watch<ThemeModeProvider>();
    final location = context.watch<LocationProvider>();
    final localeProvider = context.watch<LocaleProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final garmentCount = wardrobe.garments.length;
    final outfitCount = favorites.favorites.length;
    final minutesSaved = outfitCount * 8;
    final timeSavedLabel = minutesSaved >= 60
        ? '${(minutesSaved / 60).toStringAsFixed(1)}h'
        : '$minutesSaved min';

    return GlassSheetSurface(
      showHandle: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: ShapeDecoration(
                      color: scheme.outlineVariant,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const _ProfileHeader(),
                const SizedBox(height: 24),
                _StatsCard(
                  garmentCount: garmentCount,
                  outfitCount: outfitCount,
                  timeSavedLabel: timeSavedLabel,
                ),
                const SizedBox(height: 28),
                Text(
                  t.t('profile_settings'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                _SettingsTile(
                  icon: Icons.tune_outlined,
                  title: t.t('profile_wardrobe_settings'),
                  subtitle: t.t('profile_wardrobe_settings_subtitle'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WardrobeSettingsScreen()),
                    );
                  },
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.language_outlined,
                  title: t.t('profile_language'),
                  subtitle: localeProvider.languageCode == 'en'
                      ? t.t('onb_lang_english')
                      : t.t('onb_lang_spanish'),
                  onTap: () => _editLanguage(context),
                ),
                _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.location_on_outlined,
                  title: t.t('profile_location'),
                  subtitle: location.displayName ?? t.t('profile_location_unset'),
                  onTap: () => _editLocation(context),
                ),
                _SettingsDivider(),
                _SettingsSwitchTile(
                  icon: Icons.dark_mode_outlined,
                  title: t.t('profile_dark_mode'),
                  value: isDark,
                  onChanged: (value) {
                    HapticFeedback.selectionClick();
                    themeModeProvider.setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
                  },
                ),
                const SizedBox(height: 18),
                // Créditos de atribución exigidos por las condiciones de uso
                // de WeatherAPI.com (ver WeatherService) y por la licencia
                // CC BY 4.0 de los datos de localidades de GeoNames.org (ver
                // SpanishMunicipalitiesService): deben quedar visibles en
                // algún lugar de la app mientras se usen esos servicios/datos.
                Center(
                  child: Column(
                    children: [
                      Text(
                        t.t('profile_weather_attribution'),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.t('profile_places_attribution'),
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader();

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  @override
  void initState() {
    super.initState();
    // Relee el nombre de `SharedPreferences` en cuanto el Perfil se hace
    // visible: el onboarding pudo escribir `user_name` (al repetirlo desde
    // Ajustes del Armario) después de que `UserProfileProvider` se construyera,
    // y la app no se reinicia entre medias. `_build` escucha el provider
    // (`context.watch`), así que la UI se refresca sola al terminar.
    context.read<UserProfileProvider>().reload();
  }

  Future<void> _editName(BuildContext context, String currentName) async {
    HapticFeedback.lightImpact();
    final profile = context.read<UserProfileProvider>();
    await showSoftDialog<void>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: currentName, profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = context.watch<UserProfileProvider>().name;
    return Column(
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(
            Icons.person_outline,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 14),
        PressableScale(
          onTap: () => _editName(context, name),
          haptic: PressHaptic.selection,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: ShapeDecoration(
            color: scheme.secondary.withValues(alpha: 0.14),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eco_outlined, size: 13, color: scheme.secondary),
              const SizedBox(width: 5),
              Text(
                AppLocalizations.of(context).t('profile_capsule_wardrobe'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: scheme.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Diálogo "Editar nombre", en su propio `StatefulWidget` para que el
/// `TextEditingController` lo cree y libere el propio `State` (via
/// `dispose()`), en vez de código externo que lo destruye a mano justo
/// después de popear el diálogo.
///
/// Esto último es lo que causaba una pantalla roja al guardar: la
/// transición de salida del `AlertDialog` sigue reconstruyendo su
/// `TextField` uno o más frames después de que `Navigator.pop()` devuelve
/// el control, así que destruir el controller ahí mismo hacía que ese
/// rebuild tardío lo encontrara ya dispuesto ("used after being
/// disposed"), lo que a su vez dejaba el árbol a medio actualizar y
/// disparaba `_dependents.isEmpty` como daño colateral. Atando el
/// controller al ciclo de vida del propio `State`, Flutter solo lo destruye
/// cuando el elemento se desmonta de verdad, sea cual sea la duración real
/// de la animación de salida.
class _EditNameDialog extends StatefulWidget {
  final String initialName;
  final UserProfileProvider profile;

  const _EditNameDialog({required this.initialName, required this.profile});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isNotEmpty) {
      await widget.profile.setName(value);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      shape: squircle(20),
      title: Text(t.t('profile_edit_name')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: t.t('onb_your_name')),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.t('common_cancel')),
        ),
        PressableScale.passive(child: FilledButton(
          onPressed: _save,
          child: Text(t.t('common_save')),
        )),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final int garmentCount;
  final int outfitCount;
  final String timeSavedLabel;

  const _StatsCard({
    required this.garmentCount,
    required this.outfitCount,
    required this.timeSavedLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: ShapeDecoration(
        color: scheme.surfaceContainerHighest,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
              child: _StatItem(
                  value: '$garmentCount', label: t.t('profile_stat_garments'))),
          _StatDivider(color: scheme.outlineVariant),
          Expanded(
              child: _StatItem(
                  value: '$outfitCount', label: t.t('profile_stat_outfits'))),
          _StatDivider(color: scheme.outlineVariant),
          Expanded(
              child: _StatItem(
                  value: timeSavedLabel, label: t.t('profile_stat_time_saved'))),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;

  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            height: 1.25,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  final Color color;

  const _StatDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 34, color: color);
  }
}

class _SettingsDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 21, color: scheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 21, color: scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: scheme.secondary,
            activeTrackColor: scheme.secondary.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

/// Hoja para elegir una ciudad nueva. Se cierra devolviendo la [PlaceResult]
/// elegida (o `null` si el usuario la descarta sin elegir nada). Se puede
/// elegir de dos formas, ambas devuelven un [PlaceResult] con coordenadas ya
/// resueltas: el buscador de texto con autocompletado (respaldo local incluido)
/// o el mapa interactivo ([MapLocationPicker]).
class _LocationPickerSheet extends StatelessWidget {
  final String? current;
  final double? currentLatitude;
  final double? currentLongitude;

  const _LocationPickerSheet({
    this.current,
    this.currentLatitude,
    this.currentLongitude,
  });

  Future<void> _openMap(BuildContext context) async {
    final place = await MapLocationPicker.show(
      context,
      initialLatitude: currentLatitude,
      initialLongitude: currentLongitude,
    );
    if (place != null && context.mounted) {
      Navigator.of(context).pop(place);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return GlassSheetSurface(
      showHandle: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          24,
          14,
          24,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: ShapeDecoration(
                  color: scheme.outlineVariant,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Text(
              t.t('profile_your_city'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              current == null
                  ? t.t('profile_city_used_for_weather')
                  : t.t('profile_current_city', {'city': current!}),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            CityAutocompleteField(
              autofocus: true,
              onSelected: (place) => Navigator.of(context).pop(place),
            ),
            const SizedBox(height: 12),
            Text(
              t.t('profile_city_type_and_pick'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(
              t.t('profile_city_or_map'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            PressableScale.passive(child: OutlinedButton.icon(
              onPressed: () => _openMap(context),
              icon: const Icon(Icons.map_outlined),
              label: Text(t.t('map_select_on_map')),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: squircle(14),
              ),
            )),
          ],
        ),
      ),
    );
  }
}

/// Selector de idioma (Español / English). Se cierra devolviendo el código de
/// idioma elegido, o `null` si se descarta.
class _LanguagePickerSheet extends StatelessWidget {
  final String current;

  const _LanguagePickerSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);

    Widget option(String code, String flag, String label) {
      final selected = code == current;
      return ListTile(
        leading: Text(flag, style: const TextStyle(fontSize: 22)),
        title: Text(label),
        trailing: selected
            ? Icon(Icons.check_circle, color: scheme.primary)
            : const Icon(Icons.radio_button_unchecked),
        onTap: () => Navigator.of(context).pop(code),
      );
    }

    return GlassSheetSurface(
      showHandle: false,
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: ShapeDecoration(
                color: scheme.outlineVariant,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.t('profile_language_sheet_title'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            option('es', '🇪🇸', t.t('onb_lang_spanish')),
            option('en', '🇬🇧', t.t('onb_lang_english')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
