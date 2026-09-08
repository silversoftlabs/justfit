import 'dart:math';

import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/models/outfit_filters.dart';
import 'package:armario_virtual/services/outfit_recommendation_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prenda mínima para los tests: [tipoPrendaId] es lo único que le importa a
/// `filterGarmentsByTemperature`, el resto de campos son valores neutros que
/// no participan en la lógica bajo test.
Garment _garment(
  String id,
  GarmentCategory category, {
  String? tipoPrendaId,
  AccessoryType? accessoryType,
}) {
  return Garment(
    id: id,
    imagePath: 'path/$id.png',
    category: category,
    color: 'Negro',
    style: GarmentStyle.casual,
    tipoPrendaId: tipoPrendaId,
    accessoryType: accessoryType,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('OutfitRecommendationService.filterGarmentsByTemperature', () {
    test('a 30°C excluye sudaderas y abrigos, pero conserva una camiseta', () {
      final wardrobe = [
        _garment('sudadera', GarmentCategory.sudadera, tipoPrendaId: 'sudadera'),
        _garment('abrigo', GarmentCategory.chaqueta, tipoPrendaId: 'abrigo_parka'),
        _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
      ];

      final result = OutfitRecommendationService.filterGarmentsByTemperature(
        garments: wardrobe,
        currentTemp: 30,
      );

      final ids = result.map((g) => g.id).toSet();
      expect(ids, isNot(contains('sudadera')));
      expect(ids, isNot(contains('abrigo')));
      expect(ids, contains('camiseta'));
    });

    test(
      'a 5°C excluye camisetas de tirantes y shorts, pero conserva un abrigo',
      () {
        final wardrobe = [
          _garment('top_tirantes', GarmentCategory.camiseta, tipoPrendaId: 'top_crop'),
          _garment('shorts', GarmentCategory.pantalon, tipoPrendaId: 'shorts_bermudas'),
          _garment('abrigo', GarmentCategory.chaqueta, tipoPrendaId: 'abrigo_parka'),
        ];

        final result = OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 5,
        );

        final ids = result.map((g) => g.id).toSet();
        expect(ids, isNot(contains('top_tirantes')));
        expect(ids, isNot(contains('shorts')));
        expect(ids, contains('abrigo'));
      },
    );

    test('incluye las temperaturas límite de un rango (tempMin y tempMax)', () {
      final wardrobe = [
        _garment('sudadera', GarmentCategory.sudadera, tipoPrendaId: 'sudadera'),
      ];

      expect(
        OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 8,
        ),
        hasLength(1),
      );
      expect(
        OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 21,
        ),
        hasLength(1),
      );
      expect(
        OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 21.1,
        ),
        isEmpty,
      );
    });

    test(
      'una prenda sin tipoPrendaId (guardada antes de esta función) nunca se excluye',
      () {
        final wardrobe = [_garment('legado', GarmentCategory.sudadera)];

        final result = OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 35,
        );

        expect(result.map((g) => g.id), contains('legado'));
      },
    );

    test('armario vacío devuelve una lista vacía', () {
      expect(
        OutfitRecommendationService.filterGarmentsByTemperature(
          garments: const [],
          currentTemp: 20,
        ),
        isEmpty,
      );
    });

    test(
      'exempt conserva una prenda fuera de rango, pero el resto del armario '
      'se sigue filtrando con normalidad',
      () {
        final wardrobe = [
          _garment('sudadera', GarmentCategory.sudadera, tipoPrendaId: 'sudadera'),
          _garment('abrigo', GarmentCategory.chaqueta, tipoPrendaId: 'abrigo_parka'),
          _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
        ];

        final result = OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 30,
          exempt: (g) => g.id == 'sudadera',
        );

        final ids = result.map((g) => g.id).toSet();
        // La sudadera está fuera de su rango (8-21°C) a 30°C, pero está
        // eximida: se conserva.
        expect(ids, contains('sudadera'));
        // El abrigo NO está eximido: sigue el filtro normal y se excluye.
        expect(ids, isNot(contains('abrigo')));
        expect(ids, contains('camiseta'));
      },
    );
  });

  group('OutfitRecommendationService.generate', () {
    test('con count alto devuelve más de las 3 recomendaciones por defecto '
        'cuando el armario da para ello', () async {
      // Todas las prendas comparten color/estilo/temporada neutros, así que
      // TODAS las combinaciones top×bottom×shoe son válidas para
      // OutfitMatchingService: 3 tops × 3 bottoms × 3 shoes = 27 candidatos,
      // de sobra para que `_selectVaried` pueda devolver más de 3 sin
      // solapar demasiado entre sí.
      final wardrobe = [
        for (var i = 0; i < 3; i++) _garment('top$i', GarmentCategory.camiseta),
        for (var i = 0; i < 3; i++) _garment('bottom$i', GarmentCategory.pantalon),
        for (var i = 0; i < 3; i++) _garment('shoe$i', GarmentCategory.calzado),
      ];

      final recommendations = await OutfitRecommendationService.generate(wardrobe, count: 6);

      expect(recommendations.length, greaterThan(3));
    });

    test(
      'en ocasión deporte, nunca sugiere vaqueros aunque el armario los tenga '
      '(pero sí puede usar los joggers del mismo armario)',
      () async {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
          _garment('vaqueros', GarmentCategory.pantalon, tipoPrendaId: 'vaqueros'),
          _garment('joggers', GarmentCategory.pantalon, tipoPrendaId: 'jogger_chandal'),
          _garment('zapatillas', GarmentCategory.calzado),
        ];

        final recommendations = await OutfitRecommendationService.generate(
          wardrobe,
          occasion: OutfitOccasion.deporte,
        );

        expect(recommendations, isNotEmpty);
        final allIds = {
          for (final r in recommendations) for (final g in r.garments) g.id,
        };
        expect(allIds, isNot(contains('vaqueros')));
        expect(allIds, contains('joggers'));
      },
    );

    test(
      'a 32°C, si el usuario fija "Sudadera/Jersey" (exenta del filtro de '
      'temperatura), el outfit generado la incluye junto a prendas '
      'complementarias frescas',
      () async {
        final wardrobe = [
          // Fresca: sobrevive al filtro normal a 32°C (rango 20-45).
          _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
          // La prenda "fijada" por el usuario: fuera de su rango (8-21°C) a
          // 32°C, así que sin exención el filtro de temperatura la
          // eliminaría antes de intentar generar nada.
          _garment('sudadera', GarmentCategory.sudadera, tipoPrendaId: 'sudadera'),
          // Sin tipoPrendaId: no hay dato de temperatura del que fiarse, así
          // que sobrevive al filtro sin necesitar exención (mismo criterio
          // conservador que ya usa `filterGarmentsByTemperature`). Hace
          // falta una capa exterior compatible para que la sudadera pueda
          // formar parte de un outfit: `OutfitMatchingService` solo la
          // incluye en la combinación de 3 capas camiseta+sudadera+chaqueta,
          // nunca sola (ver `outfit_matching_service_test.dart`).
          _garment('chaqueta', GarmentCategory.chaqueta),
          // Fresco: sobrevive al filtro normal a 32°C (rango 20-45).
          _garment('shorts', GarmentCategory.pantalon, tipoPrendaId: 'shorts_bermudas'),
          _garment('zapatillas', GarmentCategory.calzado),
        ];

        final eligible = OutfitRecommendationService.filterGarmentsByTemperature(
          garments: wardrobe,
          currentTemp: 32,
          exempt: (g) => g.id == 'sudadera',
        );
        expect(eligible.map((g) => g.id), contains('sudadera'));

        final recommendations = await OutfitRecommendationService.generate(eligible, count: 5);

        expect(recommendations, isNotEmpty);
        final withSudadera = recommendations.where(
          (r) => r.garments.any((g) => g.id == 'sudadera'),
        );
        expect(
          withSudadera,
          isNotEmpty,
          reason: 'Debe existir un outfit válido que incluya la sudadera fijada',
        );
        // El pantalón fresco que la acompaña sigue siendo el filtrado por
        // temperatura con normalidad (no hay vaqueros/prendas de invierno
        // en este armario, así que basta con confirmar que el complemento
        // fresco esperado está presente).
        expect(withSudadera.first.garments.map((g) => g.id), contains('shorts'));
      },
    );

    test(
      'con "Sudadera" fijada (lockedMatch) a 35°C, sin camiseta ni chaqueta '
      'en el armario, la sudadera aparece igualmente (bypass del layering) y '
      'se elige la bermuda en vez del chándal por ser la mejor opción de '
      'temperatura disponible',
      () async {
        final wardrobe = [
          // Prenda fijada: capa media. Sin camiseta ni chaqueta con las que
          // formar la combinación normal de tres capas: sin lockedMatch,
          // generate() lanzaría Exception (mismo caso que
          // outfit_matching_service_test.dart, grupo "layering de la parte
          // superior").
          _garment('sudadera', GarmentCategory.sudadera, tipoPrendaId: 'sudadera'),
          // jogger_chandal: rango 5-22°C. A 35°C queda claramente fuera.
          _garment('chandal', GarmentCategory.pantalon, tipoPrendaId: 'jogger_chandal'),
          // shorts_bermudas: rango 20-45°C. A 35°C es la opción correcta.
          _garment('bermuda', GarmentCategory.pantalon, tipoPrendaId: 'shorts_bermudas'),
          _garment('zapatillas', GarmentCategory.calzado),
        ];

        final recommendations = await OutfitRecommendationService.generate(
          wardrobe,
          count: 1,
          currentTemp: 35,
          lockedMatch: (g) => g.category == GarmentCategory.sudadera,
        );

        expect(recommendations, isNotEmpty);
        final ids = recommendations.first.garments.map((g) => g.id).toSet();
        expect(ids, contains('sudadera'));
        expect(ids, contains('bermuda'));
        expect(ids, isNot(contains('chandal')));
      },
    );

    test(
      'con "Reloj" + "Collar" en selectedAccessories, el outfit devuelto '
      'incluye ambas prendas junto con el set de ropa (y ningún tipo no '
      'marcado, aunque haya en el armario)',
      () async {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
          _garment(
            'reloj',
            GarmentCategory.complemento,
            accessoryType: AccessoryType.reloj,
          ),
          _garment(
            'collar',
            GarmentCategory.complemento,
            accessoryType: AccessoryType.collar,
          ),
          // Tipo NO seleccionado: nunca debe aparecer en el resultado.
          _garment(
            'gorra',
            GarmentCategory.complemento,
            accessoryType: AccessoryType.gorra,
          ),
        ];

        final recommendations = await OutfitRecommendationService.generate(
          wardrobe,
          count: 1,
          selectedAccessories: [AccessoryType.reloj, AccessoryType.collar],
        );

        expect(recommendations, isNotEmpty);
        final ids = recommendations.first.garments.map((g) => g.id).toSet();
        expect(ids, containsAll(['camiseta', 'pantalon', 'calzado', 'reloj', 'collar']));
        expect(
          ids,
          isNot(contains('gorra')),
          reason: 'Un tipo no marcado en selectedAccessories nunca debe incluirse',
        );
      },
    );

    test(
      'si un tipo de selectedAccessories no tiene ninguna prenda en el '
      'armario, se omite en silencio sin bloquear la generación ni dar error',
      () async {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
          _garment(
            'reloj',
            GarmentCategory.complemento,
            accessoryType: AccessoryType.reloj,
          ),
          // Sin ninguna prenda de tipo gafas en el armario.
        ];

        final recommendations = await OutfitRecommendationService.generate(
          wardrobe,
          count: 1,
          selectedAccessories: [AccessoryType.reloj, AccessoryType.gafas],
        );

        expect(recommendations, isNotEmpty);
        final ids = recommendations.first.garments.map((g) => g.id).toSet();
        expect(ids, contains('reloj'));
        expect(ids, isNot(contains('gafas')));
      },
    );

    test(
      'el calzado es un bloque esencial: todo outfit generado incluye una prenda de calzado',
      () async {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
          _garment('vaqueros', GarmentCategory.pantalon, tipoPrendaId: 'vaqueros'),
          _garment('zapatillas', GarmentCategory.calzado, tipoPrendaId: 'zapatillas'),
        ];

        final recommendations = await OutfitRecommendationService.generate(wardrobe, count: 3);

        expect(recommendations, isNotEmpty);
        for (final r in recommendations) {
          expect(
            r.garments.any((g) => g.category == GarmentCategory.calzado),
            isTrue,
            reason: 'Cada outfit debe llevar calzado, igual que parte superior y pantalón',
          );
        }
      },
    );

    test('sin ningún calzado en el armario, generate lanza (falta un bloque esencial)', () async {
      final wardrobe = [
        _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
        _garment('vaqueros', GarmentCategory.pantalon, tipoPrendaId: 'vaqueros'),
      ];

      expect(
        () => OutfitRecommendationService.generate(wardrobe),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'en ocasión deporte se descartan los zapatos formales pero se usan las zapatillas',
      () async {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'),
          _garment('joggers', GarmentCategory.pantalon, tipoPrendaId: 'jogger_chandal'),
          _garment('formales', GarmentCategory.calzado, tipoPrendaId: 'zapatos_formales'),
          _garment('zapatillas', GarmentCategory.calzado, tipoPrendaId: 'zapatillas'),
        ];

        final recommendations = await OutfitRecommendationService.generate(
          wardrobe,
          occasion: OutfitOccasion.deporte,
        );

        expect(recommendations, isNotEmpty);
        final allIds = {
          for (final r in recommendations) for (final g in r.garments) g.id,
        };
        expect(allIds, isNot(contains('formales')));
        expect(allIds, contains('zapatillas'));
      },
    );
  });

  group('explanation localizada (parámetro l10n)', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await AppLocalizations.ensureLoaded();
    });

    List<Garment> basicWardrobe() => [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

    test('con l10n en inglés, la explicación del outfit está en inglés', () async {
      final en = await AppLocalizations.load(const Locale('en'));

      final recs = await OutfitRecommendationService.generate(
        basicWardrobe(),
        count: 1,
        l10n: en,
      );

      expect(recs.first.explanation, startsWith('This outfit'));
      expect(recs.first.explanation, isNot(contains('Este outfit')));
      expect(recs.first.explanation, isNot(contains('tonos neutros')));
    });

    test('sin l10n, la explicación se mantiene en español (por defecto)', () async {
      final recs = await OutfitRecommendationService.generate(
        basicWardrobe(),
        count: 1,
      );

      expect(recs.first.explanation, startsWith('Este outfit'));
    });
  });

  group('parámetros anti-repetición reenviados al motor', () {
    test('excludeGarmentIds pasa a través del wrapper y excluye el top', () async {
      final wardrobe = [
        _garment('topA', GarmentCategory.camiseta),
        _garment('topB', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final recommendations = await OutfitRecommendationService.generate(
        wardrobe,
        count: 5,
        excludeGarmentIds: {'topA'},
      );

      final allIds = {
        for (final r in recommendations) for (final g in r.garments) g.id,
      };
      expect(allIds, isNot(contains('topA')));
      expect(allIds, contains('topB'));
    });

    test('strictTops pasa a través del wrapper y lanza si no queda top válido', () {
      final wardrobe = [
        _garment('polo', GarmentCategory.camiseta, tipoPrendaId: 'polo'), // 15-32
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      expect(
        () => OutfitRecommendationService.generate(
          wardrobe,
          currentTemp: 33,
          strictTops: true,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('random pasa a través del wrapper: misma semilla → mismo resultado', () async {
      final wardrobe = [
        for (var i = 0; i < 3; i++) _garment('top$i', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final a = await OutfitRecommendationService.generate(
        wardrobe,
        count: 3,
        random: Random(7),
      );
      final b = await OutfitRecommendationService.generate(
        wardrobe,
        count: 3,
        random: Random(7),
      );

      expect(
        a.map((o) => o.garments.map((g) => g.id).toSet()).toList(),
        b.map((o) => o.garments.map((g) => g.id).toSet()).toList(),
      );
    });
  });
}
