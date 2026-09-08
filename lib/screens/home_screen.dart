import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../l10n/l10n_enums.dart';
import '../models/garment.dart';
import '../providers/favorite_outfits_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../theme/app_palette.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/category_badge.dart';
import '../widgets/outfit_flat_lay_view.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/shimmer_box.dart';
import 'add_garment_screen.dart';
import 'garment_detail_screen.dart';
import 'profile_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GarmentSuperCategory? _selectedSuperCategory;

  /// true mientras una [AppSnackBar] está visible: repliega el FAB de
  /// "Añadir ropa" a solo icono para cederle el ancho que la píldora
  /// necesita (ver `AppSnackBar._fabReserve`), y vuelve a `false` cuando la
  /// notificación se cierra (por su duración, por deslizarla o porque otra
  /// la reemplaza), no solo cuando termina su temporizador.
  bool _fabCompact = false;

  /// Evita solapar dos recuperaciones de captura abandonada
  /// ([_recoverAbandonedCaptureIfAny]) cuando `resumed` se dispara varias
  /// veces seguidas.
  bool _recoveringAbandonedCapture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Al arrancar en frío tras una muerte del proceso, comprobar si quedó una
    // foto de la cámara sin entregar. En cualquier otro arranque
    // `retrieveLostData` viene vacío y es un no-op barato.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recoverAbandonedCaptureIfAny());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverAbandonedCaptureIfAny());
    }
  }

  /// Red de seguridad para la captura con cámara cuando Android mata el
  /// proceso mientras la cámara está abierta (solo Android; en el resto de
  /// plataformas `retrieveLostData` siempre viene vacío). En ese caso el
  /// proceso reinicia en esta pantalla —`AddGarmentScreen` ya no existe en el
  /// árbol, así que su propia recuperación no puede ejecutarse— y aquí se
  /// reclama la foto y se reabre `AddGarmentScreen` para retomar el análisis
  /// sin que el usuario tenga que volver a hacerla. Si `AddGarmentScreen`
  /// sigue montada (el proceso no llegó a morir), se cede a su recuperación
  /// interna, que además conserva el formulario a medio rellenar.
  Future<void> _recoverAbandonedCaptureIfAny() async {
    if (AddGarmentScreen.isOpen || _recoveringAbandonedCapture) return;
    _recoveringAbandonedCapture = true;
    try {
      final LostDataResponse response = await ImagePicker().retrieveLostData();
      if (response.isEmpty || !mounted) return;
      final file = response.file;
      if (file == null) return;
      await _navigateToAddGarment(recoveredImage: file);
    } catch (e) {
      // `retrieveLostData` puede lanzar si el canal del plugin aún no está
      // listo; no es crítico (el usuario siempre puede volver a "Añadir
      // ropa") así que se ignora en vez de mostrar un aviso.
      debugPrint('[HomeScreen] retrieveLostData falló: $e');
    } finally {
      _recoveringAbandonedCapture = false;
    }
  }

  void _showDeleteSnackBar(Garment removed) {
    setState(() => _fabCompact = true);
    final t = AppLocalizations.of(context);
    final controller = AppSnackBar.show(
      context,
      t.t('home_garment_deleted'),
      type: AppSnackBarType.warning,
      actionLabel: t.t('common_undo'),
      onAction: () => context.read<WardrobeProvider>().addGarment(removed),
    );
    controller.closed.whenComplete(() {
      if (mounted) setState(() => _fabCompact = false);
    });
  }

  void _showSavedSnackBar() {
    setState(() => _fabCompact = true);
    final controller = AppSnackBar.show(
      context,
      AppLocalizations.of(context).t('home_garment_saved'),
      type: AppSnackBarType.success,
    );
    controller.closed.whenComplete(() {
      if (mounted) setState(() => _fabCompact = false);
    });
  }

  Future<void> _navigateToAddGarment({XFile? recoveredImage}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddGarmentScreen(recoveredImage: recoveredImage),
      ),
    );
    if (saved == true && mounted) _showSavedSnackBar();
  }

  String _greeting(AppLocalizations t) {
    final hour = DateTime.now().hour;
    if (hour < 12) return t.t('home_good_morning');
    if (hour < 20) return t.t('home_good_afternoon');
    return t.t('home_good_evening');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final wardrobe = context.watch<WardrobeProvider>();
    final favorites = context.watch<FavoriteOutfitsProvider>();
    final garments = wardrobe.bySuperCategory(_selectedSuperCategory);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting(t),
                          style: TextStyle(
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          t.t('nav_wardrobe'),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _ProfileAvatar(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StatsBar(
                text: t.t('home_totals', {
                  'garments': wardrobe.garments.length,
                  'outfits': favorites.favorites.length,
                }),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  t.t('home_categories'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _CategoryChip(
                    icon: Icons.checkroom_outlined,
                    label: t.t('home_all_count', {'count': wardrobe.garments.length}),
                    selected: _selectedSuperCategory == null,
                    onTap: () => setState(() => _selectedSuperCategory = null),
                  ),
                  for (final category in GarmentSuperCategory.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: _CategoryChip(
                        icon: CategoryBadge.iconForSuperCategory(category),
                        label: t.superCategory(category),
                        selected: _selectedSuperCategory == category,
                        onTap: () =>
                            setState(() => _selectedSuperCategory = category),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: wardrobe.isLoading
                  ? const _ShimmerGrid()
                  : garments.isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: _EmptyWardrobeCard(
                            hasFilter: _selectedSuperCategory != null,
                            onAdd: _navigateToAddGarment,
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: garments.length,
                          itemBuilder: (context, index) {
                            final garment = garments[index];
                            return _GarmentCard(
                              garment: garment,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => GarmentDetailScreen(garment: garment),
                                  ),
                                );
                              },
                              onDelete: () {
                                HapticFeedback.lightImpact();
                                final removed = garment;
                                context.read<WardrobeProvider>().removeGarment(removed.id);
                                _showDeleteSnackBar(removed);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: garments.isEmpty
          ? null
          : _AddGarmentFab(
              compact: _fabCompact,
              onPressed: () {
                HapticFeedback.lightImpact();
                _navigateToAddGarment();
              },
            ),
    );
  }
}

/// FAB de "Añadir ropa" que se repliega a un cuadrado de solo icono
/// (56×56, igual que un `FloatingActionButton` normal) mientras
/// [compact] es true, y vuelve a su forma extendida con etiqueta al
/// volver a `false` — ver `_HomeScreenState._showDeleteSnackBar` y el
/// artefacto de diseño "wardrobe-toast-pill".
///
/// No usa `FloatingActionButton`/`FloatingActionButton.extended`
/// directamente: Flutter no anima un cambio entre esos dos widgets (no
/// interpolan tamaño entre sí), así que aquí se replica su aspecto a mano
/// (mismo `scheme.primary`, mismo radio 16 del tema).
///
/// El `InkWell` envuelve un `Row` de tamaño natural (`MainAxisSize.min`): la
/// etiqueta simplemente deja de estar en el árbol cuando [compact], y
/// `AnimatedSize` interpola el ancho al aparecer/desaparecer. Así el área
/// pulsable SIEMPRE cubre exactamente el botón visible — antes el estado
/// replegado metía un `Row` a la fuerza en 56px, lo desbordaba y dejaba todo
/// el botón sin respuesta al tacto salvo el pixel exacto del icono.
class _AddGarmentFab extends StatelessWidget {
  final bool compact;
  final VoidCallback onPressed;

  const _AddGarmentFab({required this.compact, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return Material(
      color: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: scheme.onPrimary),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    Text(
                      t.t('home_add_clothing'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: () => ProfileSheet.show(context),
      enableHaptics: false,
      child: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.person_outline, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _StatsBar extends StatelessWidget {
  final String text;

  const _StatsBar({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: Container(
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? scheme.secondary.withValues(alpha: 0.14) : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.secondary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? scheme.secondary : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.secondary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWardrobeCard extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onAdd;

  const _EmptyWardrobeCard({required this.hasFilter, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checkroom_outlined,
            size: 72,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 20),
          Text(
            hasFilter
                ? t.t('home_empty_category_title')
                : t.t('home_empty_wardrobe_title'),
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter
                ? t.t('home_empty_category_body')
                : t.t('home_empty_wardrobe_body'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PressableScale(
            onTap: onAdd,
            haptic: PressHaptic.light,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: scheme.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    t.t('home_add_garment_cta'),
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => const ShimmerGarmentCard(),
    );
  }
}

class _GarmentCard extends StatelessWidget {
  final Garment garment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _GarmentCard({required this.garment, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final t = AppLocalizations.of(context);
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: cardElevation(context),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(8),
                child: AutocroppedGarment(
                  imagePath: garment.imagePath,
                  heroTag: 'garment-image-${garment.id}',
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: cardHairlineColor(context),
                    width: 1,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: CategoryBadge.superCategory(garment.superCategory),
              ),
              Positioned(
                top: 34,
                left: 8,
                child: CategoryBadge.style(garment.style),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    iconSize: 19,
                    splashRadius: 20,
                    onPressed: onDelete,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        t.superCategory(garment.superCategory),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${garment.color} · ${t.style(garment.style)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
