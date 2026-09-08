import 'dart:convert';

import 'package:armario_virtual/providers/favorite_outfits_provider.dart';
import 'package:armario_virtual/providers/outfit_plan_provider.dart';
import 'package:armario_virtual/providers/wardrobe_provider.dart';
import 'package:armario_virtual/screens/favorites_screen.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _fastFail = Timeout(Duration(seconds: 30));

String _seedFavorite({
  List<String> garmentIds = const ['missing-1', 'missing-2'],
  List<String> tags = const ['Trabajo', 'Elegante'],
  String? occasion,
  String? name,
}) {
  return jsonEncode([
    {
      'id': '1',
      'name': name,
      'garmentIds': garmentIds,
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'tags': tags,
      'occasion': occasion,
    },
  ]);
}

String _seedGarment({
  required String id,
  required String category,
  required String style,
  String color = 'Negro',
}) {
  return jsonEncode({
    'id': id,
    'imagePath': '/tmp/$id.png',
    'category': category,
    'color': color,
    'style': style,
    'season': 'todoElAno',
    'accessoryType': null,
    'tipoPrendaId': null,
    'isFavorite': false,
    'isArchived': false,
    'createdAt': DateTime(2026, 1, 1).toIso8601String(),
  });
}

Future<void> _pumpFavoritesScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WardrobeProvider()),
        ChangeNotifierProvider(create: (_) => FavoriteOutfitsProvider()),
        ChangeNotifierProvider(create: (_) => OutfitPlanProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: const FavoritesScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openDetailSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.checkroom_outlined).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
    'sin favoritos muestra el estado vacío con el mensaje esperado',
    (tester) async {
      SharedPreferences.setMockInitialValues({});

      await _pumpFavoritesScreen(tester);

      expect(
        find.text('Aún no has guardado ningún outfit favorito'),
        findsOneWidget,
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'un favorito guardado se pinta como tarjeta con sus tags y el corazón',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_outfits': _seedFavorite(),
      });

      await _pumpFavoritesScreen(tester);

      expect(find.text('Trabajo'), findsWidgets);
      expect(find.text('Elegante'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(
        find.text('Aún no has guardado ningún outfit favorito'),
        findsNothing,
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'la tarjeta ancha deriva los tags de los estilos de las prendas y '
    'muestra la fecha de guardado',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'wardrobe_garments': jsonEncode([
          jsonDecode(_seedGarment(id: 'g1', category: 'camiseta', style: 'casual')),
          jsonDecode(_seedGarment(id: 'g2', category: 'pantalon', style: 'formal')),
        ]),
        'favorite_outfits': _seedFavorite(
          garmentIds: ['g1', 'g2'],
          tags: ['ignorado'],
          occasion: 'Casual',
        ),
      });

      await _pumpFavoritesScreen(tester);

      expect(find.text('Casual'), findsWidgets);
      expect(find.text('Formal'), findsOneWidget);
      expect(find.text('ignorado'), findsNothing);
      expect(
        find.textContaining('Guardado el 01/01/2026'),
        findsOneWidget,
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'tocar la tarjeta abre la hoja de detalle con metadatos y acciones',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_outfits': _seedFavorite(occasion: 'Trabajo'),
      });

      await _pumpFavoritesScreen(tester);
      await _openDetailSheet(tester);

      expect(find.text('Ocasión'), findsOneWidget);
      expect(find.text('Temporada'), findsOneWidget);
      expect(find.text('Guardado'), findsOneWidget);
      expect(find.text('Ponérmelo hoy'), findsOneWidget);
      expect(find.text('Editar'), findsOneWidget);
      expect(find.text('Eliminar de favoritos'), findsOneWidget);
    },
    timeout: _fastFail,
  );

  testWidgets(
    '"Ponérmelo hoy" cierra la hoja y confirma con un snackbar',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_outfits': _seedFavorite(occasion: 'Trabajo'),
      });

      await _pumpFavoritesScreen(tester);
      await _openDetailSheet(tester);

      await tester.tap(find.text('Ponérmelo hoy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Guardado como tu outfit de hoy'), findsOneWidget);
      expect(find.text('Ponérmelo hoy'), findsNothing);
    },
    timeout: _fastFail,
  );

  testWidgets(
    'editar renombra el outfit y actualiza la tarjeta',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_outfits': _seedFavorite(occasion: 'Trabajo'),
      });

      await _pumpFavoritesScreen(tester);
      await _openDetailSheet(tester);

      await tester.tap(find.text('Editar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField).first, 'Look oficina');
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Look oficina'), findsWidgets);
    },
    timeout: _fastFail,
  );
}
