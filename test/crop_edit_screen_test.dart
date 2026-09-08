import 'dart:typed_data';

import 'package:armario_virtual/screens/crop_edit_screen.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _fastFail = Timeout(Duration(seconds: 30));

/// PNG RGBA de prueba: mitad izquierda opaca (la "prenda"), mitad derecha
/// semi-transparente (resto de fondo mal recortado), para poder ejercitar
/// tanto el pincel de borrar como el de restaurar sobre un caso real.
Uint8List _testGarmentPng({int size = 60}) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final leftHalf = x < size / 2;
      image.setPixelRgba(x, y, 0x20, 0x40, 0x80, leftHalf ? 255 : 40);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// Pantalla anfitriona mínima con un botón que empuja [CropEditScreen], para
/// poder comprobar el flujo de navegación real (push + recibir el resultado
/// al hacer pop) sin depender del resto de `AddGarmentScreen` (selección de
/// foto, segmentación U2-Netp...), que no es lo que este test cubre.
class _Harness extends StatefulWidget {
  final Uint8List imageBytes;
  const _Harness({required this.imageBytes});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  Uint8List? result;
  bool opened = false;

  Future<void> _open() async {
    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropEditScreen(imageBytes: widget.imageBytes)),
    );
    setState(() {
      opened = true;
      result = edited;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          ElevatedButton(onPressed: _open, child: const Text('Abrir editor')),
          if (opened) Text(result == null ? 'sin resultado' : 'resultado:${result!.length}'),
        ],
      ),
    );
  }
}

/// `AppPalette` es una extensión de tema que `CropEditScreen` necesita para
/// pintar el fondo neutro tras la prenda transparente (ver `_harness` en
/// `outfit_flat_lay_view_test.dart` para el mismo requisito).
Widget _app(Widget home) => MaterialApp(
  theme: ThemeData(extensions: const [AppPalette.light]),
  home: home,
);

/// Bombea hasta que [predicate] sea true, alternando pumps normales con
/// huecos REALES (`tester.runAsync`): tanto `compute()` (isolate del
/// decodificado inicial) como `ui.decodeImageFromPixels` hacen trabajo
/// asíncrono real que no avanza solo con el reloj simulado de
/// `flutter_test` (mismo motivo documentado en
/// `outfit_flat_lay_view_test.dart`).
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxAttempts = 60,
}) async {
  await tester.pump();
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (predicate()) return;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

/// Busca el propio `IconButton` de "Deshacer" (no el `Tooltip` que lo envuelve
/// por dentro: `find.byTooltip` da con ese widget interno, cuyo hit test no
/// coincide con el área visible del botón, así que ni sirve para comprobar
/// `onPressed` ni para tocarlo con `tester.tap`).
final _undoButton = find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Deshacer',
);

bool _undoEnabled(WidgetTester tester) {
  if (_undoButton.evaluate().isEmpty) return false;
  return tester.widget<IconButton>(_undoButton).onPressed != null;
}

/// Invoca `onPressed` directamente en vez de `tester.tap`: el `IconButton`
/// de la AppBar vive dentro de un `Tooltip`/`RenderSemanticsAnnotations` cuyo
/// centro reportado por `tester.getCenter` no siempre coincide con su área
/// pintable en este árbol de test, así que un tap por coordenadas es frágil
/// aquí. Llamar al callback directamente ejercita la misma lógica
/// (`_CropEditScreenState._undo`) sin depender de esa geometría.
Future<void> _tapUndo(WidgetTester tester) async {
  tester.widget<IconButton>(_undoButton).onPressed!();
  await tester.pump();
}

void main() {
  testWidgets('tocar "Abrir editor" navega a CropEditScreen y carga la imagen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_Harness(imageBytes: _testGarmentPng())));

    expect(find.byType(CropEditScreen), findsNothing);

    await tester.tap(find.text('Abrir editor'));
    await _pumpUntil(tester, () => find.text('Ajustar recorte').evaluate().isNotEmpty);

    expect(find.byType(CropEditScreen), findsOneWidget);
    await _pumpUntil(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);

    // Controles esperados: modos de pincel, slider de tamaño, deshacer y
    // aplicar.
    expect(find.text('Restaurar'), findsOneWidget);
    expect(find.text('Borrar'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(_undoButton, findsOneWidget);
    expect(find.text('Aplicar cambios'), findsOneWidget);

    // Sin ningún trazo todavía, deshacer debe estar deshabilitado.
    expect(_undoEnabled(tester), isFalse);
  }, timeout: _fastFail);

  testWidgets(
    'pintar un trazo habilita deshacer, y aplicar cambios devuelve un PNG editado',
    (tester) async {
      await tester.pumpWidget(_app(_Harness(imageBytes: _testGarmentPng())));

      await tester.tap(find.text('Abrir editor'));
      await _pumpUntil(tester, () => find.text('Restaurar').evaluate().isNotEmpty);

      final canvas = find.byKey(const Key('cropEditCanvas'));
      expect(canvas, findsOneWidget);

      // Trazo dentro del lienzo: por defecto el modo es "Borrar", así que
      // esto debe tocar el canal alfa de la imagen de trabajo.
      await tester.dragFrom(tester.getCenter(canvas), const Offset(30, 0));
      await _pumpUntil(tester, () => _undoEnabled(tester));
      expect(_undoEnabled(tester), isTrue);

      // Deshacer el trazo deja el historial vacío otra vez.
      await _tapUndo(tester);
      await _pumpUntil(tester, () => !_undoEnabled(tester));
      expect(_undoEnabled(tester), isFalse);

      // Repetir el trazo y aplicar: el editor debe hacer pop con el PNG
      // resultante, no con la instancia original.
      await tester.dragFrom(tester.getCenter(canvas), const Offset(30, 0));
      await _pumpUntil(tester, () => _undoEnabled(tester));

      await tester.tap(find.text('Aplicar cambios'));
      await _pumpUntil(tester, () => find.byType(CropEditScreen).evaluate().isEmpty);

      expect(find.byType(CropEditScreen), findsNothing);
      expect(find.textContaining('resultado:'), findsOneWidget);

      final state = tester.state<_HarnessState>(find.byType(_Harness));
      final resultBytes = state.result;
      expect(resultBytes, isNotNull);
      expect(img.decodePng(resultBytes!), isNotNull);
    },
    timeout: _fastFail,
  );
}
