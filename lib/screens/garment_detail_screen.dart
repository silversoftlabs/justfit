import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/garment.dart';
import '../models/tipo_prenda.dart';
import '../providers/wardrobe_provider.dart';
import '../services/versatility_service.dart';
import '../theme/app_palette.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/category_badge.dart';
import '../widgets/outfit_flat_lay_view.dart';
import '../widgets/versatility_badge.dart';
import '../theme/ios_design.dart';
import '../widgets/pressable_scale.dart';

class GarmentDetailScreen extends StatelessWidget {
  final Garment garment;

  const GarmentDetailScreen({super.key, required this.garment});

  Future<void> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showSoftDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: squircle(20),
        title: const Text('Eliminar prenda'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          PressableScale.passive(child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          )),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await context.read<WardrobeProvider>().removeGarment(garment.id);
    if (!context.mounted) return;
    AppSnackBar.show(context, 'Prenda eliminada', type: AppSnackBarType.success);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    final wardrobe = context.watch<WardrobeProvider>().garments;
    final versatility = VersatilityService.score(garment, wardrobe);
    final typeLabel = garment.tipoPrenda?.nombre ?? garment.superCategory.label;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(title: Text(typeLabel)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          kPageMargin,
          glassBodyTopPadding(context) + 12,
          kPageMargin,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            decoration: ShapeDecoration(
              color: scheme.surfaceContainerHighest,
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
              ),
              shadows: cardElevation(context),
            ),
            child: ClipRSuperellipse(
              borderRadius: radius,
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: AutocroppedGarment(
                        imagePath: garment.imagePath,
                        heroTag: 'garment-image-${garment.id}',
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: RoundedSuperellipseBorder(
                        borderRadius: radius,
                        side: BorderSide(color: cardHairlineColor(context),
                          width: 1,),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: CategoryBadge.garmentType(garment),
                  ),
                  Positioned(
                    top: 34,
                    left: 8,
                    child: CategoryBadge.style(garment.style),
                  ),
                  Positioned(
                    top: 60,
                    left: 8,
                    child: VersatilityBadge(score: versatility),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(typeLabel, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${garment.color} · ${garment.style.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 28),
          PressableScale.passive(child: FilledButton.tonalIcon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar prenda'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              // El fondo tonal por defecto (`secondaryContainer`) choca con el
              // rojo del texto/icono; se usa el par de error del tema
              // (`errorContainer` se define en main.dart para ambos modos).
              foregroundColor: scheme.error,
              backgroundColor: scheme.errorContainer,
            ),
          )),
        ],
      ),
    );
  }
}
