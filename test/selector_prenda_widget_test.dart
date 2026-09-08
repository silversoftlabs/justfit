import 'package:armario_virtual/models/tipo_prenda.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:armario_virtual/widgets/selector_prenda_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _fastFail = Timeout(Duration(seconds: 30));

/// Monta `SelectorPrendaWidget` solo, con el mismo `AppPalette` que usa la
/// app real (el widget lo requiere vía `Theme.of(context).extension`).
Future<void> _pumpSelector(
  WidgetTester tester, {
  TipoPrenda? seleccionInicial,
  ValueChanged<TipoPrenda>? onPrendaSeleccionada,
}) async {
  // Tamaño suficiente para que las 10 prendas de "Superiores" (el grupo más
  // grande, 4 filas de 3 columnas) quepan sin necesitar scroll: el grid es
  // `GridView.builder` y no construye las tarjetas fuera del viewport.
  tester.view.physicalSize = const Size(420, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [AppPalette.light]),
      home: Scaffold(
        body: SelectorPrendaWidget(
          seleccionInicial: seleccionInicial,
          onPrendaSeleccionada: onPrendaSeleccionada ?? (_) {},
        ),
      ),
    ),
  );
}

TipoPrenda _tipo(String id) => tiposDePrenda.firstWhere((t) => t.id == id);

void main() {
  group('SelectorPrendaWidget', () {
    testWidgets(
      'sin selección inicial arranca en Superiores mostrando sus 10 prendas',
      (tester) async {
        await _pumpSelector(tester);

        expect(find.text('Camiseta'), findsOneWidget);
        expect(find.text('Polo'), findsOneWidget);
        expect(find.text('Chaleco'), findsOneWidget);
        // Una prenda de otro grupo no debe aparecer todavía.
        expect(find.text('Vaqueros'), findsNothing);
        expect(find.text('Vestido'), findsNothing);
        expect(find.text('Cinturones'), findsNothing);
      },
      timeout: _fastFail,
    );

    testWidgets(
      'cambiar de segmento filtra el grid al grupo elegido',
      (tester) async {
        await _pumpSelector(tester);

        await tester.tap(find.text('Inferior'));
        await tester.pumpAndSettle();
        expect(find.text('Vaqueros'), findsOneWidget);
        expect(find.text('Falda'), findsOneWidget);
        expect(find.text('Leggings'), findsOneWidget);
        expect(find.text('Camiseta'), findsNothing);

        await tester.tap(find.text('Calzado'));
        await tester.pumpAndSettle();
        expect(find.text('Zapatillas'), findsOneWidget);
        expect(find.text('Zapatos Formales'), findsOneWidget);
        expect(find.text('Botas'), findsOneWidget);
        expect(find.text('Sandalias'), findsOneWidget);
        expect(find.text('Vaqueros'), findsNothing);

        await tester.tap(find.text('Enteros'));
        await tester.pumpAndSettle();
        expect(find.text('Vestido'), findsOneWidget);
        expect(find.text('Mono / Peto'), findsOneWidget);
        expect(find.text('Traje Completo'), findsOneWidget);
        expect(find.text('Zapatillas'), findsNothing);

        await tester.tap(find.text('Accesorios'));
        await tester.pumpAndSettle();
        expect(find.text('Cinturones'), findsOneWidget);
        expect(find.text('Bolsos y Mochilas'), findsOneWidget);
        expect(find.text('Joyería y Relojes'), findsOneWidget);
        expect(find.text('Otros Accesorios'), findsOneWidget);
        expect(find.text('Vestido'), findsNothing);
      },
      timeout: _fastFail,
    );

    testWidgets(
      'tocar una tarjeta dispara onPrendaSeleccionada con el tipo correcto',
      (tester) async {
        TipoPrenda? seleccionado;
        await _pumpSelector(
          tester,
          onPrendaSeleccionada: (t) => seleccionado = t,
        );

        await tester.tap(find.text('Polo'));
        await tester.pumpAndSettle();

        expect(seleccionado?.id, 'polo');
        expect(seleccionado?.grupo, GrupoPrenda.superiores);
      },
      timeout: _fastFail,
    );

    testWidgets(
      'seleccionInicial fija el grupo activo al abrir el selector',
      (tester) async {
        await _pumpSelector(tester, seleccionInicial: _tipo('falda'));

        // Arranca ya en "Inferiores" (el grupo de "Falda"), no en Superiores.
        expect(find.text('Falda'), findsOneWidget);
        expect(find.text('Camiseta'), findsNothing);
      },
      timeout: _fastFail,
    );

    testWidgets(
      'tocar una tarjeta de Calzado devuelve el tipo del grupo calzado',
      (tester) async {
        TipoPrenda? seleccionado;
        await _pumpSelector(
          tester,
          onPrendaSeleccionada: (t) => seleccionado = t,
        );

        await tester.tap(find.text('Calzado'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Botas'));
        await tester.pumpAndSettle();

        expect(seleccionado?.id, 'botas');
        expect(seleccionado?.grupo, GrupoPrenda.calzado);
      },
      timeout: _fastFail,
    );

    testWidgets(
      'las 5 etiquetas del SegmentedButton caben en una sola línea en un '
      'móvil estrecho, sin overflow',
      (tester) async {
        // 360px de ancho lógico es el móvil Android más estrecho habitual
        // (p.ej. Galaxy S8) y donde antes se veía el salto de línea.
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: const [AppPalette.light]),
            home: Scaffold(body: SelectorPrendaWidget(onPrendaSeleccionada: (_) {})),
          ),
        );

        // Un `RenderFlex`/texto desbordado lanza un FlutterError capturado
        // aquí por el framework de test; si el ajuste de estilo no basta,
        // este assert falla en vez de quedar en un false positive silencioso.
        expect(tester.takeException(), isNull);

        for (final grupo in GrupoPrenda.values) {
          final textWidget = tester.widget<Text>(find.text(grupo.label));
          final renderParagraph =
              tester.renderObject<RenderParagraph>(find.text(grupo.label));
          expect(
            renderParagraph.size.height,
            lessThan((textWidget.style?.fontSize ?? 14) * 1.6),
            reason: '"${grupo.label}" se está partiendo en más de una línea',
          );
        }
      },
      timeout: _fastFail,
    );
  });
}
