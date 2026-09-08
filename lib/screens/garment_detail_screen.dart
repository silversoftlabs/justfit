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

class GarmentDetailScreen extends StatelessWidget {
  final Garment garment;

  const GarmentDetailScreen({super.key, required this.garment});

  Future<void> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final scheme = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar prenda'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
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
      appBar: AppBar(title: Text(typeLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: scheme.surfaceContainerHighest,
              boxShadow: cardElevation(context),
            ),
            child: ClipRRect(
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
          FilledButton.tonalIcon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar prenda'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: scheme.error,
              // En modo oscuro el fondo tonal por defecto (`secondaryContainer`)
              // es un morado apagado que choca con el rojo del texto/icono; se
              // sustituye por un rojo translúcido acorde a la acción destructiva.
              // En modo claro se deja el tonal por defecto (null).
              backgroundColor: scheme.brightness == Brightness.dark
                  ? scheme.error.withValues(alpha: 0.16)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
