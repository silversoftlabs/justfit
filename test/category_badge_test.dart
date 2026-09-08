import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/widgets/category_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Brightness brightness, Widget badge) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: badge)),
    ),
  );
}

Color _labelColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  final label = GarmentSuperCategory.parteSuperior.label;

  testWidgets(
    'en modo oscuro el letrero de la supercategoría usa un salvia profundo '
    '(contraste alto sobre el pill claro)',
    (tester) async {
      await _pump(
        tester,
        Brightness.dark,
        CategoryBadge.superCategory(GarmentSuperCategory.parteSuperior),
      );

      expect(_labelColor(tester, label), const Color(0xFF33473B));
    },
  );

  testWidgets(
    'en modo claro el letrero sigue usando el color primario del tema',
    (tester) async {
      final theme = ThemeData(brightness: Brightness.light);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child:
                  CategoryBadge.superCategory(GarmentSuperCategory.parteSuperior),
            ),
          ),
        ),
      );

      expect(_labelColor(tester, label), theme.colorScheme.primary);
    },
  );

  testWidgets(
    'un badge con foreground explícito (estilo) no se ve afectado por el modo',
    (tester) async {
      await _pump(
        tester,
        Brightness.dark,
        CategoryBadge.style(GarmentStyle.casual),
      );

      expect(
        _labelColor(tester, GarmentStyle.casual.label),
        Colors.white,
      );
    },
  );
}
