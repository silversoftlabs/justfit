import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/garment.dart';
import '../models/outfit_filters.dart';
import '../models/planned_outfit.dart';
import '../providers/outfit_plan_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../services/outfit_recommendation_service.dart';
import '../theme/app_palette.dart';
import '../widgets/ai_outfit_card.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/garment_image.dart';
import '../widgets/pressable_scale.dart';

const _monthNames = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];
// Lunes-primero, coincide con DateTime.weekday (1=lunes..7=domingo).
const _weekdayShort = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime day) => _dateOnly(day).subtract(Duration(days: day.weekday - 1));

String _weekRangeLabel(DateTime start) {
  final end = start.add(const Duration(days: 6));
  if (start.month == end.month) {
    return '${start.day} - ${end.day} de ${_monthNames[start.month - 1]}';
  }
  return '${start.day} de ${_monthNames[start.month - 1]} - ${end.day} de ${_monthNames[end.month - 1]}';
}

/// Planificador semanal de outfits: permite asignar un outfit a un día de la
/// semana actual y ver de un vistazo qué días ya tienen uno planificado.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _weekStart = _mondayOf(DateTime.now());
  late DateTime _selectedDay = _dateOnly(DateTime.now());

  void _shiftWeek(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _selectedDay = _weekStart;
    });
  }

  void _selectDay(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() => _selectedDay = day);
  }

  void _goToDate(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _weekStart = _mondayOf(day);
      _selectedDay = _dateOnly(day);
    });
  }

  void _openAssignment(DateTime day, {bool startWithAi = false}) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignmentSheet(day: day, startWithAi: startWithAi),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final planProvider = context.watch<OutfitPlanProvider>();
    final wardrobe = context.watch<WardrobeProvider>().garments;
    final byId = {for (final g in wardrobe) g.id: g};
    final today = _dateOnly(DateTime.now());
    final weekDays = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    final selectedPlan = planProvider.planForDate(_selectedDay);

    final upcoming = planProvider.plans.where((p) => !p.date.isBefore(today)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Planificador',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  _WeekStrip(
                    weekStart: _weekStart,
                    days: weekDays,
                    selectedDay: _selectedDay,
                    today: today,
                    hasPlan: (d) => planProvider.planForDate(d) != null,
                    onSelectDay: _selectDay,
                    onPrevWeek: () => _shiftWeek(-1),
                    onNextWeek: () => _shiftWeek(1),
                  ),
                  const SizedBox(height: 24),
                  selectedPlan == null
                      ? _EmptyDayCard(
                          onTap: () => _openAssignment(_selectedDay, startWithAi: true),
                        )
                      : _PlannedDayCard(
                          plan: selectedPlan,
                          byId: byId,
                          onChange: () => _openAssignment(_selectedDay),
                        ),
                  const SizedBox(height: 28),
                  _UpcomingSection(
                    plans: upcoming.take(4).toList(),
                    byId: byId,
                    onTapPlan: (p) => _goToDate(p.date),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final List<DateTime> days;
  final DateTime selectedDay;
  final DateTime today;
  final bool Function(DateTime) hasPlan;
  final ValueChanged<DateTime> onSelectDay;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;

  const _WeekStrip({
    required this.weekStart,
    required this.days,
    required this.selectedDay,
    required this.today,
    required this.hasPlan,
    required this.onSelectDay,
    required this.onPrevWeek,
    required this.onNextWeek,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onPrevWeek,
              icon: Icon(Icons.chevron_left, color: scheme.onSurface),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                _weekRangeLabel(weekStart),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              onPressed: onNextWeek,
              icon: Icon(Icons.chevron_right, color: scheme.onSurface),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: _WeekDayCell(
                  weekdayLabel: _weekdayShort[day.weekday - 1],
                  dayNumber: day.day,
                  selected: day == selectedDay,
                  isToday: day == today,
                  hasPlan: hasPlan(day),
                  onTap: () => onSelectDay(day),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekDayCell extends StatelessWidget {
  final String weekdayLabel;
  final int dayNumber;
  final bool selected;
  final bool isToday;
  final bool hasPlan;
  final VoidCallback onTap;

  const _WeekDayCell({
    required this.weekdayLabel,
    required this.dayNumber,
    required this.selected,
    required this.isToday,
    required this.hasPlan,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = selected ? scheme.onPrimary : scheme.onSurface;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: Column(
        children: [
          Text(
            weekdayLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : Colors.transparent,
              border: !selected && isToday ? Border.all(color: scheme.primary, width: 1.4) : null,
            ),
            child: Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasPlan ? dotColor : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Miniatura de prenda con fondo blanco limpio, o un icono de reemplazo si
/// la prenda fue eliminada del armario tras planificarse.
class _PlanThumb extends StatelessWidget {
  final Garment? garment;

  const _PlanThumb({required this.garment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(14)),
      child: garment == null
          ? Icon(Icons.help_outline, color: scheme.outline, size: 22)
          : GarmentImage(imagePath: garment!.imagePath, fit: BoxFit.contain),
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  final VoidCallback onTap;

  const _EmptyDayCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardHairlineColor(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.checkroom_outlined, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(
            'Sin outfit asignado',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
          ),
          const SizedBox(height: 5),
          Text(
            'Elige qué ponerte este día',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onTap,
              icon: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 18),
              label: Text(
                'Añadir Outfit con IA',
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannedDayCard extends StatelessWidget {
  final PlannedOutfit plan;
  final Map<String, Garment> byId;
  final VoidCallback onChange;

  const _PlannedDayCard({required this.plan, required this.byId, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final occasion = plan.occasion;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardHairlineColor(context)),
        boxShadow: cardElevation(context, strength: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Outfit del día',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
              ),
              if (occasion != null && occasion.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    occasion,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.secondary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < plan.garmentIds.length; i++) ...[
                  Expanded(child: _PlanThumb(garment: byId[plan.garmentIds[i]])),
                  if (i != plan.garmentIds.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.autorenew, size: 18),
              label: const Text('Cambiar Outfit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingSection extends StatelessWidget {
  final List<PlannedOutfit> plans;
  final Map<String, Garment> byId;
  final ValueChanged<PlannedOutfit> onTapPlan;

  const _UpcomingSection({required this.plans, required this.byId, required this.onTapPlan});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Eventos próximos',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
        const SizedBox(height: 12),
        if (plans.isEmpty)
          Text(
            'No tienes outfits planificados próximamente.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          )
        else
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: plans.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final plan = plans[i];
                Garment? firstGarment;
                for (final id in plan.garmentIds) {
                  final g = byId[id];
                  if (g != null) {
                    firstGarment = g;
                    break;
                  }
                }
                return PressableScale(
                  onTap: () => onTapPlan(plan),
                  haptic: PressHaptic.selection,
                  child: Container(
                    width: 168,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cardHairlineColor(context)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              color: scheme.surfaceContainerHighest,
                              child: firstGarment == null
                                  ? Icon(Icons.checkroom_outlined, color: scheme.onSurfaceVariant)
                                  : GarmentImage(imagePath: firstGarment.imagePath, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_weekdayShort[plan.date.weekday - 1]} ${plan.date.day}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (plan.occasion == null || plan.occasion!.isEmpty)
                                    ? 'Outfit'
                                    : plan.occasion!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Hoja de asignación para un día: si ya tiene un outfit planificado lo
/// muestra con opciones de reasignar/quitar; si no, ofrece dos vías para
/// elegir uno nuevo: a mano (por categoría) o generado con IA.
class _AssignmentSheet extends StatefulWidget {
  final DateTime day;
  final bool startWithAi;

  const _AssignmentSheet({required this.day, this.startWithAi = false});

  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  bool _reassigning = false;

  Garment? _top;
  Garment? _bottom;
  Garment? _shoes;
  OutfitOccasion? _occasion;

  bool _aiLoading = false;
  String? _aiError;
  List<OutfitRecommendation>? _aiOutfits;

  Future<void> _pickGarment(List<Garment> options, ValueChanged<Garment> onPicked) async {
    final picked = await showModalBottomSheet<Garment>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: options.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No tienes prendas en esta categoría.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final g in options)
                    ListTile(
                      leading: SizedBox(
                        width: 44,
                        height: 44,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GarmentImage(imagePath: g.imagePath, fit: BoxFit.cover),
                        ),
                      ),
                      title: Text('${g.superCategory.label} · ${g.color}'),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop(g);
                      },
                    ),
                ],
              ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _saveManual() async {
    final ids = [_top, _bottom, _shoes].whereType<Garment>().map((g) => g.id).toList();
    if (ids.isEmpty) {
      AppSnackBar.show(context, 'Elige al menos una prenda', type: AppSnackBarType.error);
      return;
    }
    HapticFeedback.mediumImpact();
    await context
        .read<OutfitPlanProvider>()
        .assignOutfit(widget.day, ids, occasion: _occasion?.label);
    if (!mounted) return;
    AppSnackBar.show(context, 'Outfit asignado', type: AppSnackBarType.success);
    Navigator.of(context).pop();
  }

  Future<void> _generateAi() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final garments = context.read<WardrobeProvider>().garments;
      final outfits = await OutfitRecommendationService.generate(garments);
      if (!mounted) return;
      setState(() => _aiOutfits = outfits);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _assignFromAi(OutfitRecommendation outfit) async {
    HapticFeedback.mediumImpact();
    await context.read<OutfitPlanProvider>().assignOutfit(
          widget.day,
          outfit.garments.map((g) => g.id).toList(),
          occasion: outfit.occasion,
        );
    if (!mounted) return;
    AppSnackBar.show(context, 'Outfit asignado', type: AppSnackBarType.success);
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    HapticFeedback.mediumImpact();
    await context.read<OutfitPlanProvider>().removeAssignment(widget.day);
    if (!mounted) return;
    AppSnackBar.show(context, 'Asignación eliminada', type: AppSnackBarType.warning);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<OutfitPlanProvider>().planForDate(widget.day);
    final wardrobe = context.watch<WardrobeProvider>().garments;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: (plan != null && !_reassigning)
              ? _buildExistingPlan(context, plan, wardrobe)
              : _buildPicker(context, wardrobe),
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildExistingPlan(BuildContext context, PlannedOutfit plan, List<Garment> wardrobe) {
    final byId = {for (final g in wardrobe) g.id: g};
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        _buildHandle(context),
        Row(
          children: [
            Expanded(
              child: Text('Outfit asignado', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (plan.occasion != null && plan.occasion!.isNotEmpty)
              Chip(label: Text(plan.occasion!), visualDensity: VisualDensity.compact),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 96,
          child: Row(
            children: [
              for (final id in plan.garmentIds) ...[
                Expanded(
                  child: byId.containsKey(id)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: GarmentImage(imagePath: byId[id]!.imagePath, fit: BoxFit.cover),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.help_outline, color: scheme.outline),
                        ),
                ),
                if (id != plan.garmentIds.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _reassigning = true);
                },
                icon: const Icon(Icons.autorenew),
                label: const Text('Reasignar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar'),
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPicker(BuildContext context, List<Garment> wardrobe) {
    final tops = wardrobe.where((g) => topGarmentCategories.contains(g.category)).toList();
    final bottoms = wardrobe.where((g) => g.category == GarmentCategory.pantalon).toList();
    final shoes = wardrobe.where((g) => g.category == GarmentCategory.calzado).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.startWithAi ? 1 : 0,
      child: Column(
        children: [
          _buildHandle(context),
          const TabBar(
            tabs: [Tab(text: 'Elegir a mano'), Tab(text: 'Generar con IA')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _ManualSlot(
                      label: 'superior',
                      garment: _top,
                      onTap: () => _pickGarment(tops, (g) => setState(() => _top = g)),
                    ),
                    const SizedBox(height: 12),
                    _ManualSlot(
                      label: 'inferior',
                      garment: _bottom,
                      onTap: () => _pickGarment(bottoms, (g) => setState(() => _bottom = g)),
                    ),
                    const SizedBox(height: 12),
                    _ManualSlot(
                      label: 'calzado',
                      garment: _shoes,
                      onTap: () => _pickGarment(shoes, (g) => setState(() => _shoes = g)),
                    ),
                    const SizedBox(height: 20),
                    Text('Ocasión (opcional)', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in OutfitOccasion.values)
                          ChoiceChip(
                            label: Text(o.label),
                            selected: _occasion == o,
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              setState(() => _occasion = _occasion == o ? null : o);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _saveManual,
                      icon: const Icon(Icons.check),
                      label: const Text('Guardar'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _aiLoading ? null : _generateAi,
                      icon: _aiLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.smart_toy_outlined),
                      label: Text(_aiLoading ? 'Generando...' : 'Generar sugerencias'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                    if (_aiError != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _aiError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    if (_aiOutfits != null) ...[
                      const SizedBox(height: 20),
                      for (final outfit in _aiOutfits!) ...[
                        AiOutfitCard(outfit: outfit, onTap: () => _assignFromAi(outfit)),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualSlot extends StatelessWidget {
  final String label;
  final Garment? garment;
  final VoidCallback onTap;

  const _ManualSlot({required this.label, required this.garment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: garment == null
                    ? Container(
                        color: scheme.surface,
                        child: Icon(Icons.checkroom, color: scheme.outline),
                      )
                    : GarmentImage(imagePath: garment!.imagePath, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                garment == null
                    ? 'Elegir $label'
                    : '${garment!.superCategory.label} · ${garment!.color}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}
