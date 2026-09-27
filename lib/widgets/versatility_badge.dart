import 'package:flutter/material.dart';

/// Insignia flotante que muestra la puntuación de versatilidad de una
/// prenda (p.ej. "8.5/10"), con un tono de color según el tramo de la
/// puntuación. Solo usa `Theme.of(context).colorScheme`, así que se adapta
/// automáticamente al modo oscuro sin necesitar tokens propios.
class VersatilityBadge extends StatelessWidget {
  final double score;

  const VersatilityBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = score >= 8
        ? (scheme.secondary.withValues(alpha: 0.18), scheme.secondary)
        : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: bg,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_graph_outlined, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              '${score.toStringAsFixed(1)}/10',
              style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
