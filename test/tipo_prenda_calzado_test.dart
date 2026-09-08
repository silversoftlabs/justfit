import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/models/tipo_prenda.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('grupo Calzado', () {
    final calzado = tiposDePrenda.where((t) => t.grupo == GrupoPrenda.calzado).toList();

    test('el catálogo incluye los tipos de calzado estándar', () {
      final ids = calzado.map((t) => t.id).toSet();
      expect(
        ids,
        containsAll(<String>{'zapatillas', 'zapatos_formales', 'botas', 'botines', 'sandalias'}),
      );
    });

    test('todo tipo de calzado mapea a GarmentCategory.calzado', () {
      for (final tipo in calzado) {
        expect(
          tipo.categoria,
          GarmentCategory.calzado,
          reason: '${tipo.id} debería ser GarmentCategory.calzado',
        );
      }
    });

    test('el calzado no es un accesorio: accessoryType es null', () {
      for (final tipo in calzado) {
        expect(tipo.accessoryType, isNull);
      }
    });

    test('los rangos de temperatura son coherentes (sandalias con calor, botas con frío)', () {
      final sandalias = tiposDePrenda.firstWhere((t) => t.id == 'sandalias');
      final botas = tiposDePrenda.firstWhere((t) => t.id == 'botas');
      expect(sandalias.tempMin, greaterThanOrEqualTo(18));
      expect(botas.tempMax, lessThanOrEqualTo(18));
      for (final tipo in calzado) {
        expect(tipo.tempMin, lessThan(tipo.tempMax));
      }
    });

    test('cada GrupoPrenda tiene una etiqueta no vacía de una sola palabra', () {
      for (final grupo in GrupoPrenda.values) {
        expect(grupo.label.trim(), isNotEmpty);
        expect(grupo.label.contains(' '), isFalse);
      }
    });
  });
}
