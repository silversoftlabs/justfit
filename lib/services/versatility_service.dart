import 'dart:math';

import '../models/garment.dart';
import '../models/garment_options.dart';

/// Calcula una puntuación de versatilidad (0.0-10.0) para una prenda a
/// partir del propio armario del usuario: cuántas combinaciones cruza con
/// otras prendas, si sirve para cualquier temporada y si su color es
/// neutro. Es un cálculo local, instantáneo y siempre actualizado (no
/// depende de Gemini ni se persiste).
class VersatilityService {

  static double score(Garment garment, List<Garment> wardrobe) {
    final others = wardrobe.where((w) => w.id != garment.id).toList();
    final combos = _comboCount(garment, others);

    // El número de combinaciones domina la puntuación, con retornos
    // decrecientes (raíz cuadrada) para que no haga falta un armario enorme
    // para acercarse al máximo.
    final pairingScore = (sqrt(combos.toDouble()) * 2.5).clamp(0.0, 10.0);
    final seasonBonus = garment.season == GarmentSeason.todoElAno ? 1.5 : 0.0;
    final colorBonus = GarmentPalette.isNeutral(garment.color) ? 1.5 : 0.0;

    return (pairingScore * 0.7 + seasonBonus + colorBonus).clamp(0.0, 10.0);
  }

  static int _comboCount(Garment g, List<Garment> others) {
    int countIn(GarmentCategory c) =>
        others.where((w) => w.category == c && _compatible(g, w)).length;
    int countInTops() =>
        others.where((w) => topGarmentCategories.contains(w.category) && _compatible(g, w)).length;

    // Un complemento no es una prenda "core" del outfit (top/pantalón/
    // calzado): su versatilidad es cuántos TRÍOS completos podría acompañar,
    // no cuántas parejas de otra categoría, así que cruza las tres en vez de
    // solo dos.
    if (g.category == GarmentCategory.complemento) {
      return countInTops() * countIn(GarmentCategory.pantalon) * countIn(GarmentCategory.calzado);
    }
    if (topGarmentCategories.contains(g.category)) {
      return countIn(GarmentCategory.pantalon) * countIn(GarmentCategory.calzado);
    }
    if (g.category == GarmentCategory.pantalon) {
      return countInTops() * countIn(GarmentCategory.calzado);
    }
    // calzado
    return countInTops() * countIn(GarmentCategory.pantalon);
  }

  /// Dos prendas se consideran compatibles si comparten estilo, si alguna
  /// de las dos tiene un color neutro (combina con casi todo) o si alguna
  /// sirve para cualquier temporada.
  static bool _compatible(Garment a, Garment b) {
    if (a.style == b.style) return true;
    if (GarmentPalette.isNeutral(a.color) || GarmentPalette.isNeutral(b.color)) return true;
    if (a.season == GarmentSeason.todoElAno || b.season == GarmentSeason.todoElAno) return true;
    return false;
  }
}
