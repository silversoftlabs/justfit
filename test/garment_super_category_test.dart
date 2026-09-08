import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/providers/wardrobe_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Garment _garment(
  String id,
  GarmentCategory category, {
  String? tipoPrendaId,
}) {
  return Garment(
    id: id,
    imagePath: 'path/$id.png',
    category: category,
    color: 'Negro',
    style: GarmentStyle.casual,
    tipoPrendaId: tipoPrendaId,
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('Garment.superCategory', () {
    test('camiseta y sudadera se agrupan en "Parte superior"', () {
      expect(
        _garment('a', GarmentCategory.camiseta).superCategory,
        GarmentSuperCategory.parteSuperior,
      );
      expect(
        _garment('b', GarmentCategory.sudadera).superCategory,
        GarmentSuperCategory.parteSuperior,
      );
    });

    test('pantalon -> "Parte inferior"', () {
      expect(
        _garment('a', GarmentCategory.pantalon).superCategory,
        GarmentSuperCategory.parteInferior,
      );
    });

    test('chaqueta -> "Abrigos"', () {
      expect(
        _garment('a', GarmentCategory.chaqueta).superCategory,
        GarmentSuperCategory.abrigos,
      );
    });

    test('calzado -> "Calzado"', () {
      expect(
        _garment('a', GarmentCategory.calzado).superCategory,
        GarmentSuperCategory.calzado,
      );
    });

    test('complemento -> "Accesorios"', () {
      expect(
        _garment('a', GarmentCategory.complemento).superCategory,
        GarmentSuperCategory.accesorios,
      );
    });

    test(
      'una prenda de una sola pieza (vestido/mono/traje, guardada como '
      'camiseta) se reconoce como "Pieza única" por su tipoPrendaId',
      () {
        for (final id in piezaUnicaTipoPrendaIds) {
          expect(
            _garment('g', GarmentCategory.camiseta, tipoPrendaId: id)
                .superCategory,
            GarmentSuperCategory.piezaUnica,
            reason: 'tipoPrendaId "$id" debería ser piezaUnica',
          );
        }
      },
    );

    test(
      'una camiseta antigua sin tipoPrendaId cae en "Parte superior" (no hay '
      'dato para distinguir un vestido legado)',
      () {
        expect(
          _garment('a', GarmentCategory.camiseta).superCategory,
          GarmentSuperCategory.parteSuperior,
        );
      },
    );

    test('cada GarmentSuperCategory tiene una etiqueta no vacía', () {
      for (final c in GarmentSuperCategory.values) {
        expect(c.label, isNotEmpty);
      }
    });
  });

  group('WardrobeProvider.bySuperCategory', () {
    test('filtra el armario por supercategoría; null devuelve todo', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = WardrobeProvider();
      var guard = 0;
      while (provider.isLoading && guard++ < 1000) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      await provider.addGarment(_garment('camiseta', GarmentCategory.camiseta));
      await provider.addGarment(_garment('sudadera', GarmentCategory.sudadera));
      await provider.addGarment(_garment('pantalon', GarmentCategory.pantalon));
      await provider.addGarment(
        _garment('vestido', GarmentCategory.camiseta, tipoPrendaId: 'vestido'),
      );

      expect(
        provider
            .bySuperCategory(GarmentSuperCategory.parteSuperior)
            .map((g) => g.id),
        unorderedEquals(['camiseta', 'sudadera']),
      );
      expect(
        provider
            .bySuperCategory(GarmentSuperCategory.piezaUnica)
            .map((g) => g.id),
        ['vestido'],
      );
      expect(
        provider.bySuperCategory(GarmentSuperCategory.calzado),
        isEmpty,
      );
      expect(provider.bySuperCategory(null).length, 4);
    });
  });
}
