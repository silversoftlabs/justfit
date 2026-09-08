import 'dart:math';

import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/models/outfit_filters.dart';
import 'package:armario_virtual/services/outfit_matching_service.dart';
import 'package:armario_virtual/services/outfit_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prenda mínima para los tests: color neutro y mismo estilo/temporada por
/// defecto para que [OutfitMatchingService] la considere compatible con
/// cualquier otra sin que el color/estilo/temporada interfieran con lo que
/// cada test quiere aislar (las reglas de layering entre capas).
Garment _garment(
  String id,
  GarmentCategory category, {
  String color = 'Negro',
  GarmentStyle style = GarmentStyle.casual,
  GarmentSeason season = GarmentSeason.todoElAno,
  String? tipoPrendaId,
}) {
  return Garment(
    id: id,
    imagePath: 'path/$id.png',
    category: category,
    color: color,
    style: style,
    season: season,
    tipoPrendaId: tipoPrendaId,
    createdAt: DateTime(2024, 1, 1),
  );
}

/// Todas las prendas de todos los outfits generados, para comprobar
/// presencia/ausencia de una prenda concreta en el conjunto de sugerencias.
Set<String> _allGarmentIds(List<OutfitRecommendation> outfits) {
  return {for (final o in outfits) for (final g in o.garments) g.id};
}

void main() {
  group('layering de la parte superior', () {
    test('una sudadera sin camiseta ni chaqueta no forma ningún outfit', () {
      final wardrobe = [
        _garment('sudadera', GarmentCategory.sudadera),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      expect(
        () => OutfitMatchingService.generate(wardrobe),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'sudadera con camiseta pero sin chaqueta: capa base + intermedia '
      '(Opción B del sistema de capas) es válida y la sudadera SÍ aparece, '
      'sin necesitar una capa exterior',
      () {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('sudadera', GarmentCategory.sudadera),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

        final outfits = OutfitMatchingService.generate(wardrobe);

        expect(outfits, isNotEmpty);
        expect(_allGarmentIds(outfits), contains('sudadera'));
        expect(_allGarmentIds(outfits), contains('camiseta'));
      },
    );

    test('sudadera con chaqueta pero sin camiseta: la sudadera nunca aparece', () {
      final wardrobe = [
        _garment('chaqueta', GarmentCategory.chaqueta),
        _garment('sudadera', GarmentCategory.sudadera),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(wardrobe);

      expect(outfits, isNotEmpty);
      expect(_allGarmentIds(outfits), isNot(contains('sudadera')));
      expect(_allGarmentIds(outfits), contains('chaqueta'));
    });

    test(
      'camiseta + sudadera + chaqueta compatibles entre sí generan un outfit con las tres capas a la vez',
      () {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('sudadera', GarmentCategory.sudadera),
          _garment('chaqueta', GarmentCategory.chaqueta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

        // count alto: con el sistema de capas ampliado ahora hay 5 formas
        // posibles de parte superior (base sola, exterior sola, base+media,
        // base+exterior, las tres juntas), todas empatadas en puntuación en
        // este armario neutro — count:3 no garantizaría que la de 3 capas
        // esté entre las devueltas.
        final outfits = OutfitMatchingService.generate(wardrobe, count: 10);

        final layeredOutfit = outfits.where(
          (o) => {'camiseta', 'sudadera', 'chaqueta'}
              .every((id) => o.garments.any((g) => g.id == id)),
        );
        expect(
          layeredOutfit,
          isNotEmpty,
          reason: 'Debe existir al menos un outfit con camiseta+sudadera+chaqueta a la vez',
        );
      },
    );

    test(
      'camiseta y chaqueta incompatibles entre sí nunca aparecen juntas (ni '
      'en las 3 capas ni en la Opción C base+exterior), aunque cada una siga '
      'siendo compatible con la sudadera por separado (Opción B)',
      () {
        // trabajo <-> deportivo son incompatibles directamente entre
        // camiseta y chaqueta, pero casual (la sudadera, y el pantalón/
        // calzado) combina con las dos por separado: si el motor solo
        // comprobara compatibilidad "capa adyacente" en vez de TODOS los
        // pares, la combinación de 3 capas (o la Opción C base+exterior)
        // colaría igualmente.
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta, style: GarmentStyle.trabajo),
          _garment('sudadera', GarmentCategory.sudadera, style: GarmentStyle.casual),
          _garment('chaqueta', GarmentCategory.chaqueta, style: GarmentStyle.deportivo),
          _garment('pantalon', GarmentCategory.pantalon, style: GarmentStyle.casual),
          _garment('calzado', GarmentCategory.calzado, style: GarmentStyle.casual),
        ];

        final outfits = OutfitMatchingService.generate(wardrobe);

        // Opción B: camiseta + sudadera (sin chaqueta) sí es válida ahora.
        expect(_allGarmentIds(outfits), contains('sudadera'));
        expect(_allGarmentIds(outfits), contains('chaqueta'));
        // Pero nunca juntas: eso exigiría camiseta+chaqueta compatibles
        // (Opción C o las 3 capas), y no lo son.
        final sudaderaYChaqueta = outfits.where(
          (o) =>
              o.garments.any((g) => g.id == 'sudadera') &&
              o.garments.any((g) => g.id == 'chaqueta'),
        );
        expect(sudaderaYChaqueta, isEmpty);
      },
    );

    test(
      'camisa + chaqueta compatibles entre sí, sin intermedia, forman un '
      'outfit con ambas capas a la vez (Opción C base+exterior)',
      () {
        final wardrobe = [
          _garment('camisa', GarmentCategory.camiseta),
          _garment('chaqueta', GarmentCategory.chaqueta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

        final outfits = OutfitMatchingService.generate(wardrobe);

        final combined = outfits.where(
          (o) =>
              o.garments.any((g) => g.id == 'camisa') &&
              o.garments.any((g) => g.id == 'chaqueta'),
        );
        expect(
          combined,
          isNotEmpty,
          reason: 'Debe existir un outfit con camisa+chaqueta juntas, sin sudadera de por medio',
        );
      },
    );

    test(
      'un chaleco (categoría chaqueta, tipoPrendaId "chaleco") se trata como '
      'capa intermedia, no exterior: puede combinarse con una camiseta '
      'debajo Y una chaqueta de verdad encima a la vez, como cualquier '
      'jersey/sudadera',
      () {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          Garment(
            id: 'chaleco',
            imagePath: 'path/chaleco.png',
            category: GarmentCategory.chaqueta,
            color: 'Negro',
            style: GarmentStyle.casual,
            tipoPrendaId: 'chaleco',
            createdAt: DateTime(2024, 1, 1),
          ),
          _garment('chaqueta', GarmentCategory.chaqueta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

        // count alto para no depender del desempate entre candidatos
        // empatados en puntuación: con solo 5 posibles, count:10 garantiza
        // que todos (incluida la combinación de 3 capas) se devuelvan.
        final outfits = OutfitMatchingService.generate(wardrobe, count: 10);

        final threeLayers = outfits.where(
          (o) => {'camiseta', 'chaleco', 'chaqueta'}.every(
            (id) => o.garments.any((g) => g.id == id),
          ),
        );
        expect(
          threeLayers,
          isNotEmpty,
          reason: 'Solo es posible si el chaleco se clasifica como capa intermedia '
              '(distinta de la chaqueta, capa exterior de verdad)',
        );
      },
    );

    test(
      'con lockedMatch en una capa intermedia (jersey/cárdigan, representada '
      'como GarmentCategory.sudadera) y una camiseta compatible disponible '
      'en el armario, el motor busca automáticamente esa capa base en vez de '
      'dejar la intermedia sola',
      () {
        final wardrobe = [
          _garment('camiseta', GarmentCategory.camiseta),
          _garment('jersey', GarmentCategory.sudadera),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

        final outfits = OutfitMatchingService.generate(
          wardrobe,
          count: 1,
          lockedMatch: (g) => g.category == GarmentCategory.sudadera,
        );

        expect(outfits, isNotEmpty);
        final ids = outfits.first.garments.map((g) => g.id).toSet();
        expect(ids, contains('jersey'));
        expect(
          ids,
          contains('camiseta'),
          reason: 'El motor debe buscar la capa base (camiseta) para acompañar '
              'a la capa intermedia fijada, no dejarla suelta pudiendo evitarlo',
        );
      },
    );

    test('camiseta sola y chaqueta sola se siguen generando como antes (sin sudadera)', () {
      final wardrobe = [
        _garment('camiseta', GarmentCategory.camiseta),
        _garment('chaqueta', GarmentCategory.chaqueta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(wardrobe, count: 3);

      final ids = _allGarmentIds(outfits);
      expect(ids, contains('camiseta'));
      expect(ids, contains('chaqueta'));
    });
  });

  group('excludeGarmentIds (rotación obligatoria de la parte superior)', () {
    test('con 2+ tops elegibles, ninguna sugerencia incluye el top excluido', () {
      final wardrobe = [
        _garment('topA', GarmentCategory.camiseta),
        _garment('topB', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        count: 5,
        excludeGarmentIds: {'topA'},
      );

      expect(outfits, isNotEmpty);
      expect(_allGarmentIds(outfits), isNot(contains('topA')));
      expect(_allGarmentIds(outfits), contains('topB'));
    });

    test('si el top excluido es el único, se restaura el bucket (aparece igual)', () {
      final wardrobe = [
        _garment('topB', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        excludeGarmentIds: {'topB'},
      );

      expect(_allGarmentIds(outfits), contains('topB'));
    });

    test('la prenda fijada por lockedMatch nunca se excluye aunque esté en la lista', () {
      final wardrobe = [
        _garment('camiseta', GarmentCategory.camiseta),
        _garment('jersey', GarmentCategory.sudadera),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        count: 1,
        lockedMatch: (g) => g.category == GarmentCategory.sudadera,
        excludeGarmentIds: {'jersey'},
      );

      expect(outfits.first.garments.map((g) => g.id), contains('jersey'));
    });
  });

  group('penalización por uso reciente (cooldown)', () {
    test('previousOutfitIds hunde el top del outfit actual: gana otro top equivalente', () {
      final wardrobe = [
        _garment('topA', GarmentCategory.camiseta),
        _garment('topB', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        count: 1,
        previousOutfitIds: {'topA', 'pantalon', 'calzado'},
      );

      final ids = outfits.first.garments.map((g) => g.id).toSet();
      expect(ids, contains('topB'));
      expect(ids, isNot(contains('topA')));
    });

    test('una prenda solo penalizada (no excluida) sigue usándose si es la única opción', () {
      final wardrobe = [
        _garment('topA', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        recentGarmentIds: {'topA', 'pantalon', 'calzado'},
        previousOutfitIds: {'topA', 'pantalon', 'calzado'},
      );

      expect(_allGarmentIds(outfits), contains('topA'));
    });
  });

  group('strictTops', () {
    test('a 33°C descarta tops fuera de rango y sin tipoPrendaId; usa solo el válido', () {
      final wardrobe = [
        _garment('bueno', GarmentCategory.camiseta, tipoPrendaId: 'camiseta'), // 20-45
        _garment('polo', GarmentCategory.camiseta, tipoPrendaId: 'polo'), // 15-32
        _garment('sinTipo', GarmentCategory.camiseta), // sin dato -> fuera en estricto
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        count: 5,
        currentTemp: 33,
        strictTops: true,
      );

      final ids = _allGarmentIds(outfits);
      expect(ids, contains('bueno'));
      expect(ids, isNot(contains('polo')));
      expect(ids, isNot(contains('sinTipo')));
    });

    test('si strictTops deja el bucket base vacío, generate lanza (alimenta la cascada)', () {
      final wardrobe = [
        _garment('polo', GarmentCategory.camiseta, tipoPrendaId: 'polo'), // 15-32
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      expect(
        () => OutfitMatchingService.generate(
          wardrobe,
          currentTemp: 33,
          strictTops: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('selección con azar ponderado', () {
    List<Garment> equalTopsWardrobe() => [
          _garment('top0', GarmentCategory.camiseta),
          _garment('top1', GarmentCategory.camiseta),
          _garment('top2', GarmentCategory.camiseta),
          _garment('pantalon', GarmentCategory.pantalon),
          _garment('calzado', GarmentCategory.calzado),
        ];

    test('random == null → siempre el mejor candidato determinista', () {
      final wardrobe = equalTopsWardrobe();
      final a = OutfitMatchingService.generate(wardrobe, count: 1);
      final b = OutfitMatchingService.generate(wardrobe, count: 1);
      expect(
        a.first.garments.map((g) => g.id).toSet(),
        b.first.garments.map((g) => g.id).toSet(),
      );
    });

    test('misma semilla → mismo resultado (reproducible)', () {
      final wardrobe = equalTopsWardrobe();
      final a = OutfitMatchingService.generate(wardrobe, count: 3, random: Random(42));
      final b = OutfitMatchingService.generate(wardrobe, count: 3, random: Random(42));
      expect(
        a.map((o) => o.garments.map((g) => g.id).toSet()).toList(),
        b.map((o) => o.garments.map((g) => g.id).toSet()).toList(),
      );
    });

    test('semillas distintas → la parte superior elegida varía entre ejecuciones', () {
      final tops = <String>{};
      for (var seed = 0; seed < 25; seed++) {
        final outfits = OutfitMatchingService.generate(
          equalTopsWardrobe(),
          count: 1,
          random: Random(seed),
        );
        tops.add(
          outfits.first.garments.firstWhere((g) => g.category == GarmentCategory.camiseta).id,
        );
      }
      expect(tops.length, greaterThan(1));
    });
  });

  group('fallback por proximidad — garantía de resultado', () {
    test(
      'prendas de estilos incompatibles entre sí NO bloquean: devuelve un outfit completo',
      () {
        final wardrobe = [
          _garment('top', GarmentCategory.camiseta, style: GarmentStyle.deportivo),
          _garment('pantalon', GarmentCategory.pantalon, style: GarmentStyle.elegante),
          _garment('calzado', GarmentCategory.calzado, style: GarmentStyle.formal),
        ];

        final outfits = OutfitMatchingService.generate(wardrobe);

        expect(outfits, isNotEmpty);
        final ids = outfits.first.garments.map((g) => g.id).toSet();
        expect(ids, containsAll(<String>{'top', 'pantalon', 'calzado'}));
      },
    );

    test('colores que chocan entre todas las piezas tampoco bloquean', () {
      final wardrobe = [
        _garment('top', GarmentCategory.camiseta, color: 'Rojo'),
        _garment('pantalon', GarmentCategory.pantalon, color: 'Verde'),
        _garment('calzado', GarmentCategory.calzado, color: 'Amarillo'),
      ];

      final outfits = OutfitMatchingService.generate(wardrobe);

      expect(outfits, isNotEmpty);
      expect(
        outfits.first.garments.map((g) => g.id).toSet(),
        containsAll(<String>{'top', 'pantalon', 'calzado'}),
      );
    });

    test('sin combinación 100% válida, prioriza la proximidad de estilo a la ocasión', () {
      final wardrobe = [
        _garment('top', GarmentCategory.camiseta, style: GarmentStyle.elegante, color: 'Rojo'),
        _garment('panElegante', GarmentCategory.pantalon,
            style: GarmentStyle.elegante, color: 'Verde'),
        _garment('panCasual', GarmentCategory.pantalon,
            style: GarmentStyle.casual, color: 'Verde'),
        _garment('calzado', GarmentCategory.calzado, style: GarmentStyle.elegante, color: 'Rojo'),
      ];

      final outfits = OutfitMatchingService.generate(
        wardrobe,
        occasion: OutfitOccasion.fiesta, // targetStyle = elegante
        count: 1,
      );

      final ids = outfits.first.garments.map((g) => g.id).toSet();
      expect(ids, contains('panElegante'));
      expect(ids, isNot(contains('panCasual')));
    });

    test('la explicación del outfit aproximado avisa de que es la opción más parecida', () {
      final wardrobe = [
        _garment('top', GarmentCategory.camiseta, style: GarmentStyle.deportivo),
        _garment('pantalon', GarmentCategory.pantalon, style: GarmentStyle.elegante),
        _garment('calzado', GarmentCategory.calzado, style: GarmentStyle.formal),
      ];

      final outfits = OutfitMatchingService.generate(wardrobe, count: 1);

      expect(outfits.first.explanation.toLowerCase(), contains('más parecida'));
    });

    test('un armario sin calzado sí lanza: es un hueco estructural, no un filtro', () {
      final wardrobe = [
        _garment('camiseta', GarmentCategory.camiseta),
        _garment('pantalon', GarmentCategory.pantalon),
      ];

      expect(
        () => OutfitMatchingService.generate(wardrobe),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('variabilidad — prendas distintas', () {
    test('todas las prendas de cada outfit generado son distintas entre sí', () {
      final wardrobe = [
        _garment('camiseta', GarmentCategory.camiseta),
        _garment('sudadera', GarmentCategory.sudadera),
        _garment('chaqueta', GarmentCategory.chaqueta),
        _garment('pantalon', GarmentCategory.pantalon),
        _garment('calzado', GarmentCategory.calzado),
      ];

      final outfits = OutfitMatchingService.generate(wardrobe, count: 10);

      expect(outfits, isNotEmpty);
      for (final o in outfits) {
        final ids = o.garments.map((g) => g.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'ninguna prenda se repite en $ids');
      }
    });

    test(
      'excluir el outfit anterior completo: la nueva sugerencia no repite ninguna de sus prendas',
      () {
        final wardrobe = [
          _garment('topA', GarmentCategory.camiseta),
          _garment('topB', GarmentCategory.camiseta),
          _garment('panA', GarmentCategory.pantalon),
          _garment('panB', GarmentCategory.pantalon),
          _garment('shoeA', GarmentCategory.calzado),
          _garment('shoeB', GarmentCategory.calzado),
        ];

        final outfits = OutfitMatchingService.generate(
          wardrobe,
          count: 5,
          excludeGarmentIds: {'topA', 'panA', 'shoeA'},
        );

        final allIds = {
          for (final o in outfits) for (final g in o.garments) g.id,
        };
        expect(allIds, isNot(contains('topA')));
        expect(allIds, isNot(contains('panA')));
        expect(allIds, isNot(contains('shoeA')));
        expect(allIds, containsAll(<String>{'topB', 'panB', 'shoeB'}));
      },
    );

    test(
      'excluir prendas que vaciarían un hueco: se restauran, nunca deja el outfit incompleto',
      () {
        final wardrobe = [
          _garment('topA', GarmentCategory.camiseta),
          _garment('topB', GarmentCategory.camiseta),
          _garment('panUnico', GarmentCategory.pantalon),
          _garment('shoeUnico', GarmentCategory.calzado),
        ];

        final outfits = OutfitMatchingService.generate(
          wardrobe,
          count: 1,
          excludeGarmentIds: {'topA', 'panUnico', 'shoeUnico'},
        );

        final ids = outfits.first.garments.map((g) => g.id).toSet();
        expect(ids, contains('topB')); // sí se rota lo que se puede
        expect(ids, contains('panUnico')); // restaurado: era el único
        expect(ids, contains('shoeUnico')); // restaurado: era el único
      },
    );
  });
}
