import 'package:flutter/material.dart';

import '../models/garment.dart';
import '../models/tipo_prenda.dart';

/// Insignia flotante compacta (icono + texto) para señalar de un vistazo la
/// categoría o el estilo de una prenda sobre su foto.
class CategoryBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? background;
  final Color? foreground;

  const CategoryBadge({
    super.key,
    required this.icon,
    required this.label,
    this.background,
    this.foreground,
  });

  factory CategoryBadge.superCategory(GarmentSuperCategory category) {
    return CategoryBadge(
      icon: iconForSuperCategory(category),
      label: category.label,
    );
  }

  /// Badge con el tipo de prenda concreto ("Sudadera / Jersey"), no la
  /// supercategoría: se usa en la pantalla de detalle, donde interesa el dato
  /// específico. Cae a la supercategoría si la prenda no tiene un
  /// [TipoPrenda] resoluble (guardada antes de `tipoPrendaId`).
  factory CategoryBadge.garmentType(Garment garment) {
    final tipo = garment.tipoPrenda;
    return CategoryBadge(
      icon: tipo?.icono ?? iconForSuperCategory(garment.superCategory),
      label: tipo?.nombre ?? garment.superCategory.label,
    );
  }

  factory CategoryBadge.style(GarmentStyle style) {
    return CategoryBadge(
      icon: Icons.style_outlined,
      label: style.label,
      background: Colors.black.withValues(alpha: 0.55),
      foreground: Colors.white,
    );
  }

  /// Icono representativo de cada supercategoría, reutilizado también por los
  /// chips de filtro en `home_screen.dart`.
  static IconData iconForSuperCategory(GarmentSuperCategory category) {
    switch (category) {
      case GarmentSuperCategory.parteSuperior:
        return Icons.checkroom_outlined;
      case GarmentSuperCategory.parteInferior:
        return Icons.straighten_outlined;
      case GarmentSuperCategory.abrigos:
        return Icons.dry_cleaning_outlined;
      case GarmentSuperCategory.piezaUnica:
        return Icons.accessibility_new_outlined;
      case GarmentSuperCategory.calzado:
        return Icons.roller_skating_outlined;
      case GarmentSuperCategory.accesorios:
        return Icons.diamond_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = background ?? Colors.white.withValues(alpha: 0.92);
    // El "pill" es blanco en ambos modos (para que se lea sobre cualquier
    // foto), así que el texto y el icono tienen que ser oscuros también en
    // modo oscuro: el `colorScheme.primary` nocturno (salvia claro) casi no
    // contrasta sobre blanco. Se usa un salvia profundo (~9:1 sobre el pill).
    final fg = foreground ??
        (isDark
            ? const Color(0xFF33473B)
            : Theme.of(context).colorScheme.primary);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: bg,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
