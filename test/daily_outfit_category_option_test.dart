import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/screens/daily_outfit_screen.dart';
import 'package:armario_virtual/services/outfit_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prenda mínima para los tests: [category]/[tipoPrendaId] son lo único que
/// le importa a `DailyOutfitCategoryOption.matches`, el resto de campos son
/// valores neutros que no participan en la lógica bajo test.
Garment _garment(GarmentCategory category, {String? tipoPrendaId}) {
  return Garment(
    id: 'g',
    imagePath: 'path/g.png',
    category: category,
    color: 'Negro',
    style: GarmentStyle.casual,
    tipoPrendaId: tipoPrendaId,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('DailyOutfitCategoryOption.matches', () {
    test('sudaderaJersey solo coincide con GarmentCategory.sudadera', () {
      expect(
        DailyOutfitCategoryOption.sudaderaJersey.matches(_garment(GarmentCategory.sudadera)),
        isTrue,
      );
      expect(
        DailyOutfitCategoryOption.sudaderaJersey.matches(_garment(GarmentCategory.camiseta)),
        isFalse,
      );
    });

    test('vaquerosPantalon solo coincide con GarmentCategory.pantalon', () {
      expect(
        DailyOutfitCategoryOption.vaquerosPantalon.matches(_garment(GarmentCategory.pantalon)),
        isTrue,
      );
      expect(
        DailyOutfitCategoryOption.vaquerosPantalon.matches(_garment(GarmentCategory.calzado)),
        isFalse,
      );
    });

    // No hay test de "accesorios": desde que los accesorios tienen su propio
    // selector independiente y de selección múltiple en
    // `daily_outfit_screen.dart` (ver `_dailyOutfitAccessoryTypes`),
    // `DailyOutfitCategoryOption` ya no tiene un valor para ellos.

    test('calzado solo coincide con GarmentCategory.calzado', () {
      expect(
        DailyOutfitCategoryOption.calzado.matches(_garment(GarmentCategory.calzado)),
        isTrue,
      );
      expect(
        DailyOutfitCategoryOption.calzado.matches(_garment(GarmentCategory.pantalon)),
        isFalse,
      );
    });

    test(
      'vestido coincide por tipoPrendaId, no por GarmentCategory '
      '(un vestido se guarda como GarmentCategory.camiseta)',
      () {
        expect(
          DailyOutfitCategoryOption.vestido.matches(
            _garment(GarmentCategory.camiseta, tipoPrendaId: 'vestido'),
          ),
          isTrue,
        );
        // Una camiseta normal comparte GarmentCategory con el vestido, pero
        // no debe contar como "vestido" sin el tipoPrendaId correspondiente.
        expect(
          DailyOutfitCategoryOption.vestido.matches(
            _garment(GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
          ),
          isFalse,
        );
        expect(
          DailyOutfitCategoryOption.vestido.matches(_garment(GarmentCategory.camiseta)),
          isFalse,
        );
      },
    );
  });

  group('DailyOutfitCategoryOption fija + OutfitRecommendationService.generate', () {
    test(
      'a 35°C, con "Sudadera / Jersey" fijada y una camiseta/chaqueta cuyo '
      'estilo no combina entre sí (bloquearían el layering en el motor '
      'normal), sigue generando un outfit con la sudadera en vez de fallar '
      '— reproduce el bug reportado en daily_outfit_screen.dart',
      () async {
        final wardrobe = [
          Garment(
            id: 'sudadera',
            imagePath: 'p/sudadera.png',
            category: GarmentCategory.sudadera,
            color: 'Negro',
            style: GarmentStyle.casual,
            tipoPrendaId: 'sudadera', // rango 8-21°C: fuera de rango a 35°C.
            createdAt: DateTime(2024, 1, 1),
          ),
          Garment(
            id: 'camiseta',
            imagePath: 'p/camiseta.png',
            category: GarmentCategory.camiseta,
            color: 'Negro',
            style: GarmentStyle.trabajo,
            tipoPrendaId: 'camiseta',
            createdAt: DateTime(2024, 1, 1),
          ),
          Garment(
            id: 'chaqueta',
            imagePath: 'p/chaqueta.png',
            category: GarmentCategory.chaqueta,
            color: 'Negro',
            // trabajo <-> deportivo son incompatibles entre sí (aunque cada
            // una combine con la sudadera casual por separado): sin
            // lockedMatch, esto bloquea la combinación de 3 capas y la
            // sudadera nunca aparece (mismo caso que
            // outfit_matching_service_test.dart).
            style: GarmentStyle.deportivo,
            createdAt: DateTime(2024, 1, 1),
          ),
          Garment(
            id: 'bermuda',
            imagePath: 'p/bermuda.png',
            category: GarmentCategory.pantalon,
            color: 'Negro',
            style: GarmentStyle.casual,
            tipoPrendaId: 'shorts_bermudas',
            createdAt: DateTime(2024, 1, 1),
          ),
          Garment(
            id: 'zapatillas',
            imagePath: 'p/zapatillas.png',
            category: GarmentCategory.calzado,
            color: 'Negro',
            style: GarmentStyle.casual,
            createdAt: DateTime(2024, 1, 1),
          ),
        ];

        const category = DailyOutfitCategoryOption.sudaderaJersey;

        // Mismo primer paso que daily_outfit_screen.dart: eximir la
        // categoría fija del filtro de temperatura antes de generar.
        final eligible = OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 35,
          exempt: category.matches,
        );
        expect(eligible.map((g) => g.id), contains('sudadera'));

        final recommendations = await OutfitRecommendationService.generate(
          eligible,
          currentTemp: 35,
          lockedMatch: category.matches,
        );

        expect(recommendations, isNotEmpty);
        expect(recommendations.first.garments.any(category.matches), isTrue);
      },
    );
  });
}
