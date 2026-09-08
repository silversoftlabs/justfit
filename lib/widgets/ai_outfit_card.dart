import 'package:flutter/material.dart';

import '../services/outfit_recommendation_service.dart';
import 'outfit_flat_lay_view.dart';

/// Tarjeta que muestra una combinación de outfit sugerida por el motor de
/// reglas local
/// (título, ocasión, prendas y explicación). Se usa tanto en la pantalla de
/// Outfits como en el selector de asignación del Calendario, donde [onTap]
/// permite elegir esa sugerencia para un día concreto.
///
/// Cada prenda se pinta con [AutocroppedGarment] (de `outfit_flat_lay_view.dart`)
/// en vez de `GarmentImage` directo: recorta el margen transparente sobrante
/// de la foto (ver el comentario de esa clase) para que ocupe el máximo
/// espacio posible dentro de su recuadro, misma mejora ya aplicada al
/// mosaico de `OutfitFlatLayView` y a `daily_outfit_screen.dart`.
///
/// No se pasa `heroTag` a ninguna imagen aquí: una misma prenda puede
/// repetirse en varias tarjetas visibles a la vez.
class AiOutfitCard extends StatelessWidget {
  final OutfitRecommendation outfit;
  final VoidCallback? onTap;

  const AiOutfitCard({super.key, required this.outfit, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              outfit.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (outfit.occasion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Chip(
                label: Text(outfit.occasion),
                visualDensity: VisualDensity.compact,
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 96,
              child: Row(
                children: [
                  for (final garment in outfit.garments) ...[
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: scheme.surfaceContainerHighest,
                          // Padding mínimo: con el margen transparente ya
                          // recortado por AutocroppedGarment, no hace falta
                          // aire extra para que la prenda se vea completa.
                          padding: const EdgeInsets.all(4),
                          child: AutocroppedGarment(imagePath: garment.imagePath),
                        ),
                      ),
                    ),
                    if (garment != outfit.garments.last) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (outfit.explanation.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                outfit.explanation,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
    );
  }
}
