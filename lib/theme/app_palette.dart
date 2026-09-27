import 'package:flutter/material.dart';

/// Paleta base "Minimalista Moderno / Warm Minimalist" (Flat 2.0) de la app:
/// fondo cálido roto, superficies en lino/crema y un verde salvia como único
/// acento. Fuente única de verdad para el [ColorScheme] construido en
/// `main.dart` y para los tokens de [AppPalette] de abajo.
class AppColors {
  /// Background de pantallas — blanco roto / arena suave.
  static const background = Color(0xFFF9F8F6);

  /// Superficie / tarjetas — crema claro / lino.
  static const surface = Color(0xFFF2ECE1);

  /// Color primario / acento — verde salvia, para elementos activos,
  /// selección y botones principales.
  static const primary = Color(0xFF6E8D77);

  /// Texto principal — gris grafito de alto contraste.
  static const textPrimary = Color(0xFF2C2C2C);

  /// Texto secundario.
  static const textSecondary = Color(0xFF757575);
}

/// Tokens de color específicos de la app (más allá del [ColorScheme]
/// estándar de Material) que necesitan una variante clara y otra oscura
/// explícita para que pantallas como `add_garment_screen.dart` se adapten
/// automáticamente al modo oscuro del sistema.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color cardBeige;
  final Color chipBeige;
  final Color chipBeigeBorder;
  final Color strongText;
  final Color favoritePinkBg;
  final Color favoritePinkText;

  /// Texto secundario/muted (subtítulos, descripciones) con contraste AA
  /// (≥4.5:1) garantizado sobre `cardBeige`/`chipBeige` y sobre el fondo
  /// base de cada modo — usar en vez de aplicar opacidad a `strongText`.
  final Color textSecondary;

  /// Iconos inactivos/decorativos (cumple el mínimo de 3:1 para elementos
  /// no textuales, ver WCAG 1.4.11).
  final Color iconMuted;

  /// Fondo decorativo detrás de la foto de una prenda en la pantalla de
  /// edición (`_ImagePickerCard`), pintado en la UI, NUNCA compuesto en los
  /// píxeles guardados: el archivo persistido tiene transparencia real (ver
  /// `image_compositor.dart`), así que este color solo simula cómo se verá
  /// la prenda cuando se muestre sobre un fondo neutro.
  final Color garmentPhotoBackground;

  const AppPalette({
    required this.cardBeige,
    required this.chipBeige,
    required this.chipBeigeBorder,
    required this.strongText,
    required this.favoritePinkBg,
    required this.favoritePinkText,
    required this.textSecondary,
    required this.iconMuted,
    required this.garmentPhotoBackground,
  });

  static const light = AppPalette(
    cardBeige: AppColors.surface,
    chipBeige: Color(0xFFEDE5D3),
    chipBeigeBorder: Color(0xFFDDD0B8),
    strongText: AppColors.textPrimary,
    favoritePinkBg: Color(0xFFE9C7CD),
    // Antes 0xFF8C4B57 (~4.1:1 sobre favoritePinkBg, por debajo de AA);
    // oscurecido para superar 4.5:1.
    favoritePinkText: Color(0xFF7D3F4A),
    textSecondary: AppColors.textSecondary,
    iconMuted: Color(0xFF9C9488),
    garmentPhotoBackground: AppColors.background,
  );

  // Fondo de tarjetas/modales #1E1E1E · elevado #262626 · borde #333333 ·
  // texto primario #F9F8F6 (≥15:1 sobre todos los fondos oscuros de arriba)
  // · texto secundario #A8A49E (gris neutro-cálido) (≥6:1 sobre todos ellos) · icono inactivo
  // #8E8E93 — ver auditoría de contraste WCAG AA.
  static const dark = AppPalette(
    cardBeige: Color(0xFF262626),
    chipBeige: Color(0xFF2E2E2E),
    chipBeigeBorder: Color(0xFF3A3A3A),
    strongText: Color(0xFFF9F8F6),
    favoritePinkBg: Color(0xFF4A2E33),
    favoritePinkText: Color(0xFFE3AEB6),
    textSecondary: Color(0xFFA8A49E),
    iconMuted: Color(0xFF8E8E93),
    garmentPhotoBackground: Color(0xFF1E1E1E),
  );

  @override
  AppPalette copyWith({
    Color? cardBeige,
    Color? chipBeige,
    Color? chipBeigeBorder,
    Color? strongText,
    Color? favoritePinkBg,
    Color? favoritePinkText,
    Color? textSecondary,
    Color? iconMuted,
    Color? garmentPhotoBackground,
  }) {
    return AppPalette(
      cardBeige: cardBeige ?? this.cardBeige,
      chipBeige: chipBeige ?? this.chipBeige,
      chipBeigeBorder: chipBeigeBorder ?? this.chipBeigeBorder,
      strongText: strongText ?? this.strongText,
      favoritePinkBg: favoritePinkBg ?? this.favoritePinkBg,
      favoritePinkText: favoritePinkText ?? this.favoritePinkText,
      textSecondary: textSecondary ?? this.textSecondary,
      iconMuted: iconMuted ?? this.iconMuted,
      garmentPhotoBackground: garmentPhotoBackground ?? this.garmentPhotoBackground,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      cardBeige: Color.lerp(cardBeige, other.cardBeige, t)!,
      chipBeige: Color.lerp(chipBeige, other.chipBeige, t)!,
      chipBeigeBorder: Color.lerp(chipBeigeBorder, other.chipBeigeBorder, t)!,
      strongText: Color.lerp(strongText, other.strongText, t)!,
      favoritePinkBg: Color.lerp(favoritePinkBg, other.favoritePinkBg, t)!,
      favoritePinkText: Color.lerp(favoritePinkText, other.favoritePinkText, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      iconMuted: Color.lerp(iconMuted, other.iconMuted, t)!,
      garmentPhotoBackground:
          Color.lerp(garmentPhotoBackground, other.garmentPhotoBackground, t)!,
    );
  }
}

/// Sombra multicapa suave para tarjetas, ajustada automáticamente para
/// seguir aportando profundidad en modo oscuro (donde una sombra negra
/// literal es invisible sobre un fondo ya casi negro).
List<BoxShadow> cardElevation(BuildContext context, {double strength = 1.0}) {
  final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: (isDark ? 0.45 : 0.10) * strength),
      blurRadius: 18,
      offset: const Offset(0, 8),
      spreadRadius: -6,
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: (isDark ? 0.20 : 0.04) * strength),
      blurRadius: 8,
      offset: const Offset(0, 1),
    ),
  ];
}

/// Borde ultrafino para tarjetas: negro sutil en modo claro, blanco sutil en
/// modo oscuro (la sombra sola no basta como pista de profundidad sobre un
/// fondo casi negro).
Color cardHairlineColor(BuildContext context) {
  final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
}
