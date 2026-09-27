import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/favorite_outfit.dart';
import '../models/garment.dart';
import '../providers/favorite_outfits_provider.dart';
import '../providers/outfit_plan_provider.dart';
import '../providers/wardrobe_provider.dart';
import '../theme/app_palette.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/outfit_flat_lay_view.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/shimmer_box.dart';
import '../theme/ios_design.dart';

/// Pestaña "Favoritos": los outfits que el usuario ha guardado con el corazón
/// desde "Outfit del día". Cada tarjeta muestra la composición completa del
/// outfit y, al tocarla, abre una hoja de detalle con metadatos y acciones.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final favorites = context.watch<FavoriteOutfitsProvider>();
    final wardrobe = context.watch<WardrobeProvider>();
    final loading = favorites.isLoading || wardrobe.isLoading;
    final entries = favorites.favorites;

    return Scaffold(
      // Transparente: deja ver el `AmbientBackdrop` de `MainNavigation`.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Favoritos',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const _ShimmerList()
                  : entries.isEmpty
                      // Padding inferior = barra de navegación: con
                      // `extendBody` el cuerpo llega hasta el borde y el
                      // estado vacío se centraría medio tapado por ella.
                      ? Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.paddingOf(context).bottom,
                          ),
                          child: const AppEmptyState(
                            icon: Icons.favorite_border,
                            title: 'Sin favoritos todavía',
                            subtitle:
                                'Aún no has guardado ningún outfit favorito',
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            kPageMargin,
                            12,
                            kPageMargin,
                            24 + MediaQuery.paddingOf(context).bottom,
                          ),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final favorite = entries[index];
                            return _FavoriteOutfitCard(
                              favorite: favorite,
                              garments: garmentsForFavorite(favorite, wardrobe),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rehidrata las prendas de un favorito contra el armario actual, descartando
/// ids que ya no existan (prenda borrada tras guardar). El orden sigue al de
/// `garmentIds`.
List<Garment> garmentsForFavorite(
  FavoriteOutfit favorite,
  WardrobeProvider wardrobe,
) {
  final byId = {for (final g in wardrobe.garments) g.id: g};
  return favorite.garmentIds
      .map((id) => byId[id])
      .whereType<Garment>()
      .toList();
}

/// Card ancha de un outfit favorito: alto fijo para que [OutfitFlatLayView]
/// (que necesita una altura acotada) pueda escalar todas las prendas.
const double _kCardHeight = 176;

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        kPageMargin,
        12,
        kPageMargin,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: 4,
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (context, index) => const ShimmerBox(
        height: _kCardHeight,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    );
  }
}

/// Tarjeta ancha (lista de 1 columna) de un outfit favorito: a la izquierda la
/// composición completa del outfit en grande, a la derecha título, tags,
/// fecha y el corazón para quitarlo. Toda la tarjeta es tappable y abre
/// [_FavoriteDetailSheet].
class _FavoriteOutfitCard extends StatelessWidget {
  final FavoriteOutfit favorite;
  final List<Garment> garments;

  const _FavoriteOutfitCard({required this.favorite, required this.garments});

  String get _title {
    final name = favorite.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    final occasion = favorite.occasion?.trim();
    if (occasion != null && occasion.isNotEmpty) return occasion;
    if (garments.isNotEmpty) return _seasonLabel(garments);
    if (favorite.tags.isNotEmpty) return favorite.tags.first;
    final count = favorite.garmentIds.length;
    return '$count ${count == 1 ? 'prenda' : 'prendas'}';
  }

  /// Tags a partir de los estilos distintos de las prendas del outfit; si el
  /// armario ya no tiene esas prendas, se cae a los tags guardados.
  List<String> get _styleTags {
    final labels = <String>[];
    for (final garment in garments) {
      final label = garment.style.label;
      if (!labels.contains(label)) labels.add(label);
    }
    return labels.isNotEmpty ? labels : favorite.tags;
  }

  Future<void> _remove(BuildContext context) async {
    HapticFeedback.lightImpact();
    final provider = context.read<FavoriteOutfitsProvider>();
    final removed = favorite;
    await provider.removeFavoriteOutfit(removed.id);
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      'Outfit quitado de favoritos',
      type: AppSnackBarType.warning,
      actionLabel: 'Deshacer',
      onAction: () => provider.addFavoriteOutfit(
        name: removed.name,
        garmentIds: removed.garmentIds,
        tags: removed.tags,
        occasion: removed.occasion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final radius = BorderRadius.circular(16);
    final tags = _styleTags;

    return PressableScale(
      onTap: () => _FavoriteDetailSheet.show(context, favorite.id),
      child: Container(
        height: _kCardHeight,
        decoration: ShapeDecoration(
          color: palette.cardBeige,
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(color: cardHairlineColor(context)),
          ),
          shadows: cardElevation(context, strength: 0.6),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lado izquierdo (~50%): visualización de ropa.
            Expanded(
              flex: 5,
              child: ClipRSuperellipse(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
                child: _OutfitPreview(garments: garments, palette: palette),
              ),
            ),
            // Lado derecho: información y acciones.
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: palette.strongText,
                              ),
                            ),
                          ),
                        ),
                        _RemoveHeartButton(onPressed: () => _remove(context)),
                      ],
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in tags.take(3))
                            _TagChip(
                              label: tag,
                              palette: palette,
                              compact: true,
                            ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Text(
                      'Guardado el ${_formatDateSlash(favorite.createdAt)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vista previa de la composición completa del outfit: usa [OutfitFlatLayView]
/// en modo franjas, que agrupa las prendas por categoría (superior / inferior
/// / calzado / accesorios) y las escala para que TODAS quepan sin recortar el
/// calzado ni los accesorios. Si no queda ninguna prenda válida, un icono.
class _OutfitPreview extends StatelessWidget {
  final List<Garment> garments;
  final AppPalette palette;

  const _OutfitPreview({required this.garments, required this.palette});

  @override
  Widget build(BuildContext context) {
    if (garments.isEmpty) {
      return Container(
        color: palette.garmentPhotoBackground,
        alignment: Alignment.center,
        child: Icon(Icons.checkroom_outlined, color: palette.iconMuted, size: 32),
      );
    }
    return OutfitFlatLayView(garments: garments, gap: 10);
  }
}

class _RemoveHeartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _RemoveHeartButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Quitar de favoritos',
      icon: Icon(Icons.favorite, color: palette.favoritePinkText),
      style: IconButton.styleFrom(
        backgroundColor: palette.favoritePinkBg.withValues(alpha: 0.85),
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(6),
      ),
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final AppPalette palette;
  final bool compact;

  const _TagChip({
    required this.label,
    required this.palette,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: palette.chipBeige,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: palette.chipBeigeBorder),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: compact ? 10.5 : 11,
          fontWeight: FontWeight.w500,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hoja de detalle
// ---------------------------------------------------------------------------

/// Franjas de un outfit para el desglose de la hoja de detalle. Mismo criterio
/// que `OutfitFlatLayView._bandFor`, reutilizando [topGarmentCategories] como
/// fuente de verdad de "qué cuenta como parte superior".
enum _OutfitBand { top, bottom, footwear, accessory }

_OutfitBand _bandOf(GarmentCategory category) {
  if (topGarmentCategories.contains(category)) return _OutfitBand.top;
  if (category == GarmentCategory.pantalon) return _OutfitBand.bottom;
  if (category == GarmentCategory.calzado) return _OutfitBand.footwear;
  return _OutfitBand.accessory;
}

String _bandLabel(_OutfitBand band) {
  switch (band) {
    case _OutfitBand.top:
      return 'Parte superior';
    case _OutfitBand.bottom:
      return 'Parte inferior';
    case _OutfitBand.footwear:
      return 'Calzado';
    case _OutfitBand.accessory:
      return 'Accesorios';
  }
}

/// Temporada del outfit: las estaciones distintas de sus prendas (ignorando
/// "Todo el año"); si no hay ninguna concreta, "Todo el año".
String _seasonLabel(List<Garment> garments) {
  final seasons = garments
      .map((g) => g.season)
      .where((s) => s != GarmentSeason.todoElAno)
      .toSet();
  if (seasons.isEmpty) return GarmentSeason.todoElAno.label;
  return GarmentSeason.values
      .where(seasons.contains)
      .map((s) => s.label)
      .join(' · ');
}

String _formatDate(DateTime date) {
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Fecha en formato dd/mm/aaaa con ceros a la izquierda.
String _formatDateSlash(DateTime date) {
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  return '$dd/$mm/${date.year}';
}

/// Hoja de detalle de un outfit favorito: vista completa por categorías,
/// metadatos (ocasión, temporada, tags, fecha) y acciones ("Ponérmelo hoy",
/// "Editar", "Eliminar de favoritos").
class _FavoriteDetailSheet extends StatelessWidget {
  /// Se identifica por id (no por el objeto) para poder re-leer el favorito
  /// actualizado del provider tras "Editar" sin cerrar la hoja.
  final String favoriteId;

  /// Contexto de la pantalla (no el de la hoja): sigue montado tras cerrar el
  /// modal, así que es el que se usa para las `AppSnackBar`.
  final BuildContext hostContext;

  const _FavoriteDetailSheet({
    required this.favoriteId,
    required this.hostContext,
  });

  static Future<void> show(BuildContext context, String favoriteId) {
    HapticFeedback.lightImpact();
    return showGlassSheet<void>(
      context: context,
      isScrollControlled: true,
      wrap: false,
      builder: (_) => _FavoriteDetailSheet(
        favoriteId: favoriteId,
        hostContext: context,
      ),
    );
  }

  FavoriteOutfit? _lookup(FavoriteOutfitsProvider provider) {
    for (final favorite in provider.favorites) {
      if (favorite.id == favoriteId) return favorite;
    }
    return null;
  }

  Future<void> _wearToday(
    BuildContext context,
    FavoriteOutfit favorite,
    List<Garment> garments,
  ) async {
    HapticFeedback.lightImpact();
    final ids = garments.isNotEmpty
        ? garments.map((g) => g.id).toList()
        : favorite.garmentIds;
    await hostContext.read<OutfitPlanProvider>().assignOutfit(
          DateTime.now(),
          ids,
          occasion: favorite.occasion,
        );
    if (context.mounted) Navigator.of(context).pop();
    if (hostContext.mounted) {
      AppSnackBar.show(hostContext, 'Guardado como tu outfit de hoy');
    }
  }

  Future<void> _edit(BuildContext context, FavoriteOutfit favorite) async {
    HapticFeedback.lightImpact();
    await showSoftDialog<void>(
      context: context,
      builder: (_) => _EditFavoriteDialog(
        favorite: favorite,
        provider: context.read<FavoriteOutfitsProvider>(),
      ),
    );
  }

  Future<void> _delete(BuildContext context, FavoriteOutfit favorite) async {
    HapticFeedback.lightImpact();
    final provider = context.read<FavoriteOutfitsProvider>();
    await provider.removeFavoriteOutfit(favorite.id);
    if (context.mounted) Navigator.of(context).pop();
    if (!hostContext.mounted) return;
    AppSnackBar.show(
      hostContext,
      'Outfit quitado de favoritos',
      type: AppSnackBarType.warning,
      actionLabel: 'Deshacer',
      onAction: () => provider.addFavoriteOutfit(
        name: favorite.name,
        garmentIds: favorite.garmentIds,
        tags: favorite.tags,
        occasion: favorite.occasion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final favorite = _lookup(context.watch<FavoriteOutfitsProvider>());

    // Se ha eliminado mientras la hoja estaba abierta: no pintar nada.
    if (favorite == null) return const SizedBox.shrink();

    final garments = garmentsForFavorite(
      favorite,
      context.watch<WardrobeProvider>(),
    );
    final title = favorite.name?.trim().isNotEmpty == true
        ? favorite.name!.trim()
        : (favorite.occasion?.trim().isNotEmpty == true
            ? favorite.occasion!.trim()
            : 'Outfit favorito');

    return GlassSheetSurface(
      showHandle: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),
                _OutfitBreakdown(garments: garments, palette: palette),
                const SizedBox(height: 24),
                _MetadataSection(favorite: favorite, garments: garments),
                const SizedBox(height: 24),
                PressableScale.passive(child: FilledButton.icon(
                  onPressed: () => _wearToday(context, favorite, garments),
                  icon: const Icon(Icons.checkroom),
                  label: const Text('Ponérmelo hoy'),
                )),
                const SizedBox(height: 10),
                PressableScale.passive(child: OutlinedButton.icon(
                  onPressed: () => _edit(context, favorite),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant),
                    shape: squircle(16),
                    minimumSize: const Size.fromHeight(48),
                  ),
                )),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _delete(context, favorite),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar de favoritos'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    minimumSize: const Size.fromHeight(48),
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

/// Desglose del outfit por categorías: una sección por franja presente, con
/// las prendas en miniaturas grandes.
class _OutfitBreakdown extends StatelessWidget {
  final List<Garment> garments;
  final AppPalette palette;

  const _OutfitBreakdown({required this.garments, required this.palette});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (garments.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: palette.garmentPhotoBackground,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cardHairlineColor(context)),
          ),
        ),
        child: Text(
          'Las prendas de este outfit ya no están en tu armario',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
        ),
      );
    }

    final byBand = <_OutfitBand, List<Garment>>{};
    for (final garment in garments) {
      byBand.putIfAbsent(_bandOf(garment.category), () => []).add(garment);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final band in _OutfitBand.values)
          if (byBand[band]?.isNotEmpty ?? false) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _bandLabel(band).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final garment in byBand[band]!)
                  _BreakdownTile(garment: garment, palette: palette),
              ],
            ),
            const SizedBox(height: 18),
          ],
      ],
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  final Garment garment;
  final AppPalette palette;

  const _BreakdownTile({required this.garment, required this.palette});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 116,
            width: 116,
            padding: const EdgeInsets.all(8),
            decoration: ShapeDecoration(
              color: palette.garmentPhotoBackground,
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: cardHairlineColor(context)),
              ),
            ),
            child: AutocroppedGarment(imagePath: garment.imagePath),
          ),
          const SizedBox(height: 6),
          Text(
            garment.accessoryType?.label ?? garment.superCategory.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.strongText,
            ),
          ),
          Text(
            garment.color,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MetadataSection extends StatelessWidget {
  final FavoriteOutfit favorite;
  final List<Garment> garments;

  const _MetadataSection({required this.favorite, required this.garments});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final tags = favorite.tags;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: palette.cardBeige,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardHairlineColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(
            label: 'Ocasión',
            child: Text(
              favorite.occasion?.trim().isNotEmpty == true
                  ? favorite.occasion!.trim()
                  : '—',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.strongText,
              ),
            ),
          ),
          _MetaRow(
            label: 'Temporada',
            child: Text(
              garments.isEmpty ? '—' : _seasonLabel(garments),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.strongText,
              ),
            ),
          ),
          _MetaRow(
            label: 'Tags',
            child: tags.isEmpty
                ? Text(
                    '—',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: palette.strongText,
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in tags)
                        _TagChip(label: tag, palette: palette),
                    ],
                  ),
          ),
          _MetaRow(
            label: 'Guardado',
            last: true,
            child: Text(
              _formatDate(favorite.createdAt),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: palette.strongText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final Widget child;
  final bool last;

  const _MetaRow({
    required this.label,
    required this.child,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: child)),
        ],
      ),
    );
  }
}

/// Diálogo "Editar": renombra el outfit y/o cambia sus tags (separados por
/// comas). En su propio `StatefulWidget` para que los `TextEditingController`
/// los gestione el `State` (mismo motivo que `_EditNameDialog` en
/// `profile_sheet.dart`: evitar "used after being disposed" en la animación
/// de salida).
class _EditFavoriteDialog extends StatefulWidget {
  final FavoriteOutfit favorite;
  final FavoriteOutfitsProvider provider;

  const _EditFavoriteDialog({required this.favorite, required this.provider});

  @override
  State<_EditFavoriteDialog> createState() => _EditFavoriteDialogState();
}

class _EditFavoriteDialogState extends State<_EditFavoriteDialog> {
  late final _nameController =
      TextEditingController(text: widget.favorite.name ?? '');
  late final _tagsController =
      TextEditingController(text: widget.favorite.tags.join(', '));

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.provider.updateFavoriteOutfit(
      widget.favorite.id,
      name: _nameController.text,
      tags: _tagsController.text.split(','),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: squircle(20),
      title: const Text('Editar outfit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Sin nombre',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tagsController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'Casual, Trabajo…',
              helperText: 'Separados por comas',
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        PressableScale.passive(child: FilledButton(onPressed: _save, child: const Text('Guardar'))),
      ],
    );
  }
}
