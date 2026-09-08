import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/garment.dart';
import '../models/wardrobe_settings.dart';
import '../providers/wardrobe_provider.dart';
import '../providers/wardrobe_settings_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/pressable_scale.dart';
import 'onboarding_screen.dart';

/// Estaciones de prenda que cubre cada preferencia de armario activo. Un
/// conjunto vacío significa "no hay nada fuera de temporada".
Set<GarmentSeason> _seasonsFor(EstacionActiva estacion) {
  switch (estacion) {
    case EstacionActiva.primaveraVerano:
      return const {GarmentSeason.primavera, GarmentSeason.verano};
    case EstacionActiva.otonoInvierno:
      return const {GarmentSeason.otono, GarmentSeason.invierno};
    case EstacionActiva.todoElAno:
      return const {};
  }
}

/// Pantalla de 'Gestión de Armario' (Ajustes del Armario): preferencias de
/// estilo/IA y acciones avanzadas sobre las prendas guardadas. Usa el tema
/// ambiente de la app (`Theme.of(context)`), así que sigue el modo
/// claro/oscuro general (`ThemeModeProvider`) en vez de forzar uno propio.
class WardrobeSettingsScreen extends StatelessWidget {
  const WardrobeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de Armario')),
      body: const SafeArea(child: _WardrobeSettingsBody()),
    );
  }
}

class _WardrobeSettingsBody extends StatelessWidget {
  const _WardrobeSettingsBody();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<WardrobeSettingsProvider>();
    if (settings.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const _SectionTitle('Estilo y Preferencias de IA'),
        const SizedBox(height: 10),
        _StyleAndAiCard(settings: settings),
        const SizedBox(height: 28),
        const _SectionTitle('Acciones Avanzadas'),
        const SizedBox(height: 10),
        const _AdvancedActionsCard(),
        const SizedBox(height: 28),
        const _SectionTitle('Introducción'),
        const SizedBox(height: 10),
        const _OnboardingCard(),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

// --- Sección 2: Estilo y Preferencias de IA -------------------------------

class _StyleAndAiCard extends StatelessWidget {
  final WardrobeSettingsProvider settings;
  const _StyleAndAiCard({required this.settings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.fromBorderSide(BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _FieldLabel('Estilo Principal'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final estilo in EstiloPrincipal.values)
                _SelectableChip(
                  label: estilo.label,
                  selected: settings.estiloPrincipal == estilo,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.read<WardrobeSettingsProvider>().setEstiloPrincipal(estilo);
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _FieldLabel('Estación Activa'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final estacion in EstacionActiva.values)
                _SelectableChip(
                  label: estacion.label,
                  selected: settings.estacionActiva == estacion,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    context.read<WardrobeSettingsProvider>().setEstacionActiva(estacion);
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          const _FieldLabel('Reglas de combinación'),
          const SizedBox(height: 4),
          Text(
            'Notas propias sobre cómo combinar tus prendas.',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < settings.reglas.length; i++)
            _ReglaRow(index: i, regla: settings.reglas[i]),
          const SizedBox(height: 8),
          const _AddReglaField(),
        ],
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.18)
              : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}

class _ReglaRow extends StatelessWidget {
  final int index;
  final ReglaCombinacion regla;
  const _ReglaRow({required this.index, required this.regla});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: regla.activa,
              onChanged: (_) {
                HapticFeedback.selectionClick();
                context.read<WardrobeSettingsProvider>().toggleRegla(index);
              },
              activeColor: scheme.primary,
              checkColor: scheme.onPrimary,
              side: BorderSide(color: scheme.onSurfaceVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              regla.texto,
              style: TextStyle(
                fontSize: 13.5,
                color: regla.activa ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
            splashRadius: 16,
            onPressed: () => context.read<WardrobeSettingsProvider>().removeRegla(index),
          ),
        ],
      ),
    );
  }
}

class _AddReglaField extends StatefulWidget {
  const _AddReglaField();

  @override
  State<_AddReglaField> createState() => _AddReglaFieldState();
}

class _AddReglaFieldState extends State<_AddReglaField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<WardrobeSettingsProvider>().addRegla(text);
    _controller.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            style: TextStyle(color: scheme.onSurface, fontSize: 13.5),
            cursorColor: scheme.primary,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Añadir regla personalizada...',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              filled: true,
              fillColor: Theme.of(context).scaffoldBackgroundColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.add_circle, color: scheme.primary),
          onPressed: _submit,
        ),
      ],
    );
  }
}

// --- Sección 3: Acciones Avanzadas ----------------------------------------

class _AdvancedActionsCard extends StatelessWidget {
  const _AdvancedActionsCard();

  Future<void> _archiveOutOfSeason(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final settings = context.read<WardrobeSettingsProvider>();
    final wardrobe = context.read<WardrobeProvider>();
    final seasons = _seasonsFor(settings.estacionActiva);
    if (seasons.isEmpty) {
      AppSnackBar.show(
        context,
        'La estación activa es "Todo el año": ninguna prenda se considera fuera de temporada.',
        type: AppSnackBarType.warning,
      );
      return;
    }
    final count = await wardrobe.archiveOutOfSeason(seasons);
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      count == 0
          ? 'No hay prendas fuera de temporada para archivar.'
          : '$count prenda${count == 1 ? '' : 's'} archivada${count == 1 ? '' : 's'}.',
      type: count == 0 ? AppSnackBarType.warning : AppSnackBarType.success,
    );
  }

  Future<void> _confirmClearWardrobe(BuildContext context) async {
    HapticFeedback.heavyImpact();
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('¿Vaciar el armario?', style: TextStyle(color: scheme.onSurface)),
        content: Text(
          'Se eliminarán todas las prendas guardadas de forma permanente. '
          'Esta acción no se puede deshacer.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancelar', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Vaciar armario'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<WardrobeProvider>().clearAll();
    if (!context.mounted) return;
    AppSnackBar.show(context, 'Armario vaciado', type: AppSnackBarType.warning);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ActionButton(
          icon: Icons.archive_outlined,
          label: 'Archivar prendas fuera de temporada',
          onTap: () => _archiveOutOfSeason(context),
        ),
        const SizedBox(height: 12),
        _ActionButton(
          icon: Icons.delete_forever_outlined,
          label: 'Vaciar armario completo',
          danger: true,
          onTap: () => _confirmClearWardrobe(context),
        ),
      ],
    );
  }
}

// --- Sección 4: Introducción --------------------------------------------

/// Relanza el onboarding (la bienvenida de cuatro slides) a pantalla completa.
/// Pone `hasCompletedOnboarding = false` y abre la `OnboardingScreen`; al
/// terminarla ("Empezar"/"Saltar") esta vuelve a marcar el flag como `true`
/// (ver `OnboardingScreen._finish`) y su `onFinished` cierra la ruta,
/// devolviendo al usuario a esta pantalla.
class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard();

  Future<void> _repeatOnboarding(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final navigator = Navigator.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasCompletedOnboarding', false);

    navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => OnboardingScreen(
          onFinished: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ActionButton(
      icon: Icons.restart_alt,
      label: 'Repetir onboarding',
      onTap: () => _repeatOnboarding(context),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    return PressableScale(
      onTap: onTap,
      haptic: danger ? PressHaptic.medium : PressHaptic.light,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
        decoration: BoxDecoration(
          color: danger ? scheme.error.withValues(alpha: 0.12) : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: danger ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: color.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}
