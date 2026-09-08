import 'package:armario_virtual/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:armario_virtual/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await AppLocalizations.ensureLoaded();
  });

  testWidgets('App loads and shows the bottom navigation tabs', (
    WidgetTester tester,
  ) async {
    // Sin esto, WardrobeProvider/OutfitPlanProvider se quedan con
    // isLoading=true para siempre en el entorno de test (SharedPreferences
    // nunca resuelve sin un mock), y la pantalla se queda mostrando el
    // shimmer indefinidamente.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ArmarioVirtualApp());
    // No se usa pumpAndSettle: la rejilla muestra un shimmer con una
    // animación en bucle infinito mientras carga, que nunca "se asienta".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Mi Armario'), findsWidgets);
    expect(find.text('Outfit del día'), findsWidgets);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
