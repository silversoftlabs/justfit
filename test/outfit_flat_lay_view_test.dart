import 'dart:io';

import 'package:armario_virtual/models/garment.dart';
import 'package:armario_virtual/theme/app_palette.dart';
import 'package:armario_virtual/widgets/outfit_flat_lay_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _fastFail = Timeout(Duration(seconds: 30));

/// Escribe un PNG RGBA de prueba a un archivo temporal y devuelve su ruta,
/// para poder construir `Garment`s reales que la vista pueda leer y recortar
/// durante el test.
Future<String> _writePngGarment(
  Directory dir,
  String name, {
  required int width,
  required int height,
}) async {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0x20, 0x40, 0x80, 255));
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(img.encodePng(image));
  return file.path;
}

Garment _garment(String id, String imagePath, GarmentCategory category) {
  return Garment(
    id: id,
    imagePath: imagePath,
    category: category,
    color: 'Azul',
    style: GarmentStyle.casual,
    season: GarmentSeason.todoElAno,
    createdAt: DateTime(2026),
  );
}

/// Envuelve el widget bajo prueba con el tema real de la app (necesario para
/// `AppPalette.garmentPhotoBackground`) dentro de un lienzo de tamaño fijo,
/// igual que lo acotaría cualquier llamador real (`SizedBox`/`Container`).
Widget _harness(Widget child, {double width = 320, double height = 300}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [AppPalette.light]),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

/// Crea un directorio temporal, escribe en él los PNG pedidos y limpia al
/// terminar. TODO el trabajo de disco corre dentro de `tester.runAsync`: el
/// cuerpo de `testWidgets` se ejecuta en la zona de tiempo simulado de
/// `flutter_test` (para que las animaciones sean deterministas), y una
/// operación de E/S real esperada directamente ahí (sin `runAsync`) nunca se
/// resuelve — el test se queda colgado en vez de fallar. `runAsync` la saca a
/// la zona real por el tiempo justo de completarla.
Future<void> _withTempPngs(
  WidgetTester tester,
  Map<String, ({int width, int height})> specs,
  Future<void> Function(Map<String, String> pathsByName) body,
) async {
  late Directory dir;
  final paths = <String, String>{};

  await tester.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('outfit_flat_lay_test');
    for (final entry in specs.entries) {
      paths[entry.key] = await _writePngGarment(
        dir,
        entry.key,
        width: entry.value.width,
        height: entry.value.height,
      );
    }
  });

  try {
    await body(paths);
  } finally {
    // Windows mantiene el archivo abierto mientras `FileImage` conserva su
    // caché de la imagen decodificada, y borrar el directorio con el handle
    // aún abierto falla con "el proceso no tiene acceso al archivo". Vaciar
    // la caché de imágenes suelta esos handles; el reintento con una pequeña
    // espera real es una red de seguridad adicional para el caso en que el
    // sistema operativo tarde un instante más en liberarlo.
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(() async {
      // Best-effort: si Windows sigue sin soltar el archivo (antivirus,
      // indexado...) tras varios reintentos, NO se relanza la excepción. Un
      // directorio temporal sin borrar es inofensivo (el sistema operativo lo
      // limpia solo); dejar que la excepción se propague aquí, en cambio, sí
      // es dañino: al ser asíncrona y no capturada a tiempo, contamina el
      // siguiente test con trabajo pendiente sin relación con lo que prueba.
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          if (await dir.exists()) await dir.delete(recursive: true);
          return;
        } on FileSystemException {
          if (attempt == 4) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });
  }
}

/// Todos los `Image` montados ya tienen un tamaño real (ancho > 0), es decir,
/// tanto el autocrop (`compute()` + lectura de archivo) como la
/// decodificación de la imagen resultante ya terminaron.
///
/// Antes de que termine el autocrop, `AutocroppedGarment` pinta un hueco en
/// blanco (sin tamaño); antes de que `Image.memory`/`Image.file` terminen de
/// decodificar, `RenderImage` no puede calcular la relación de aspecto y
/// reporta ancho 0. Cualquiera de los dos deja el árbol construido sin lanzar
/// ninguna excepción, pero una lectura de geometría global (`getTopLeft`,
/// `getRect`) sobre esa rama da NaN. Por eso no basta con esperar un tiempo
/// fijo: hay que comprobar explícitamente que todo terminó.
bool _allImagesDecoded(WidgetTester tester, int expectedCount) {
  // Mientras el autocrop está en vuelo, `AutocroppedGarment` no pinta
  // ningún `Image` todavía (hueco en blanco): comprobar solo "los Image que
  // haya, están listos" se cumple de forma vacía con 0 encontrados, dando un
  // falso "ya terminó" antes de que el primero siquiera empiece a resolver.
  // Por eso hace falta también el recuento esperado.
  final elements = find.byType(Image).evaluate();
  if (elements.length != expectedCount) return false;
  for (final element in elements) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    if (renderObject.size.width <= 0) return false;
  }
  return true;
}

/// Bombea frames hasta que todas las prendas presentes hayan terminado de
/// recortarse y decodificarse (ver [_allImagesDecoded]), alternando pumps
/// normales con huecos REALES (`tester.runAsync`): tanto el autocrop
/// (`compute()`, un isolate aparte) como la decodificación de imagen son
/// trabajo asíncrono real que corre en el reloj real, no en el simulado que
/// avanzan los `pump()` por sí solos. Sin esto, ni la escritura de archivos
/// ni el recorte ni la decodificación llegan a completarse nunca dentro de la
/// zona de tiempo simulado de `flutter_test` (ver `widget_test.dart` para el
/// mismo motivo por el que este proyecto evita `pumpAndSettle`, que tampoco
/// lo resuelve).
Future<void> _pumpUntilDecoded(
  WidgetTester tester, {
  required int expectedImages,
  int maxAttempts = 60,
}) async {
  await tester.pump();
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (_allImagesDecoded(tester, expectedImages)) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  // Margen final para que la animación de fundido (`AnimatedOpacity`,
  // 220 ms, en el camino de respaldo sin recortar) también se asiente.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('renderiza una prenda por franja sin overflow', (tester) async {
    await _withTempPngs(
      tester,
      {
        't1': (width: 400, height: 600),
        'b1': (width: 500, height: 700),
        's1': (width: 600, height: 400),
      },
      (paths) async {
        final top = _garment('t1', paths['t1']!, GarmentCategory.camiseta);
        final bottom = _garment('b1', paths['b1']!, GarmentCategory.pantalon);
        final shoe = _garment('s1', paths['s1']!, GarmentCategory.calzado);

        await tester.pumpWidget(
          _harness(OutfitFlatLayView(garments: [top, bottom, shoe])),
        );
        await _pumpUntilDecoded(tester, expectedImages: 3);

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsNWidgets(3));
      },
    );
  }, timeout: _fastFail);

  testWidgets(
    'ordena las franjas de arriba a abajo: top, bottom, calzado',
    (tester) async {
      await _withTempPngs(
        tester,
        {
          't1': (width: 400, height: 600),
          'b1': (width: 500, height: 700),
          's1': (width: 600, height: 400),
        },
        (paths) async {
          final top = _garment('t1', paths['t1']!, GarmentCategory.camiseta);
          final bottom = _garment('b1', paths['b1']!, GarmentCategory.pantalon);
          final shoe = _garment('s1', paths['s1']!, GarmentCategory.calzado);

          // Deliberadamente en orden inverso al de entrada, para comprobar
          // que el widget agrupa por categoría y no se limita a respetar el
          // orden de la lista recibida.
          await tester.pumpWidget(
            _harness(OutfitFlatLayView(garments: [shoe, bottom, top])),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);

          // Cada franja tiene una única prenda, así que el orden de aparición
          // de los `Image` en el árbol (izquierda-a-derecha, arriba-a-abajo)
          // coincide con el orden visual de las franjas: no hace falta
          // identificar cada uno por ruta para comprobar el orden top ->
          // bottom -> calzado.
          final images = find.byType(Image);
          expect(images, findsNWidgets(3));

          final y0 = tester.getTopLeft(images.at(0)).dy;
          final y1 = tester.getTopLeft(images.at(1)).dy;
          final y2 = tester.getTopLeft(images.at(2)).dy;

          expect(y0, lessThan(y1));
          expect(y1, lessThan(y2));
        },
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'varias prendas en la misma franja se centran sin solaparse',
    (tester) async {
      await _withTempPngs(
        tester,
        {'l': (width: 300, height: 500), 'r': (width: 300, height: 500)},
        (paths) async {
          final left = _garment('l', paths['l']!, GarmentCategory.camiseta);
          // chaqueta también cuenta como "top" vía topGarmentCategories.
          final right = _garment('r', paths['r']!, GarmentCategory.chaqueta);

          await tester.pumpWidget(
            _harness(OutfitFlatLayView(garments: [left, right])),
          );
          await _pumpUntilDecoded(tester, expectedImages: 2);

          expect(tester.takeException(), isNull);

          // Una sola franja con 2 prendas: el Row las coloca en el mismo
          // orden que la lista de entrada, así que .at(0) es la izquierda.
          final images = find.byType(Image);
          expect(images, findsNWidgets(2));

          final leftRect = tester.getRect(images.at(0));
          final rightRect = tester.getRect(images.at(1));

          final noOverlap =
              leftRect.right <= rightRect.left ||
              rightRect.right <= leftRect.left;
          expect(noOverlap, isTrue);
        },
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'muchas prendas en una franja no desbordan (red de seguridad FittedBox)',
    (tester) async {
      final specs = {
        for (var i = 0; i < 8; i++) 'g$i': (width: 400, height: 600),
      };

      await _withTempPngs(tester, specs, (paths) async {
        final garments = [
          for (var i = 0; i < 8; i++)
            _garment('g$i', paths['g$i']!, GarmentCategory.camiseta),
        ];

        // Lienzo deliberadamente estrecho: sin el FittedBox(scaleDown), 8
        // prendas lado a lado a su alto natural desbordarían con un
        // RenderFlex overflow error.
        await tester.pumpWidget(
          _harness(
            OutfitFlatLayView(garments: garments),
            width: 200,
            height: 300,
          ),
        );
        await _pumpUntilDecoded(tester, expectedImages: 8);

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsNWidgets(8));
      });
    },
    timeout: _fastFail,
  );

  testWidgets('pocas prendas (una sola) también renderiza sin overflow', (
    tester,
  ) async {
    await _withTempPngs(tester, {'only': (width: 400, height: 600)}, (
      paths,
    ) async {
      final single = _garment('only', paths['only']!, GarmentCategory.camiseta);

      await tester.pumpWidget(_harness(OutfitFlatLayView(garments: [single])));
      await _pumpUntilDecoded(tester, expectedImages: 1);

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });
  }, timeout: _fastFail);

  testWidgets('lista vacía no lanza excepción', (tester) async {
    await tester.pumpWidget(_harness(const OutfitFlatLayView(garments: [])));
    await _pumpUntilDecoded(tester, expectedImages: 0);

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
  }, timeout: _fastFail);

  testWidgets(
    'a tamaño de tarjeta de rejilla (108px, gap reducido) sigue siendo legible',
    (tester) async {
      await _withTempPngs(
        tester,
        {
          't1': (width: 400, height: 600),
          'b1': (width: 500, height: 700),
          's1': (width: 600, height: 400),
        },
        (paths) async {
          final top = _garment('t1', paths['t1']!, GarmentCategory.camiseta);
          final bottom = _garment('b1', paths['b1']!, GarmentCategory.pantalon);
          final shoe = _garment('s1', paths['s1']!, GarmentCategory.calzado);

          // Mismas dimensiones que usa _GridOutfitCard en outfit_screen.dart:
          // ancho típico de una celda de rejilla de 2 columnas, alto fijo de
          // 108, gap: 6 (en vez del valor por defecto 16, que a esta altura
          // dejaría casi todo el espacio en padding/separación y nada para
          // las prendas).
          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(garments: [top, bottom, shoe], gap: 6),
              width: 165,
              height: 108,
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);

          expect(tester.takeException(), isNull);
          expect(find.byType(Image), findsNWidgets(3));

          // "Legible" en concreto: cada franja debe seguir teniendo una
          // altura renderizada con dos cifras de píxeles, no un hilo de 1-2px
          // que en la práctica sería invisible/amontonado.
          for (final element in find.byType(Image).evaluate()) {
            final size = (element.renderObject! as RenderBox).size;
            expect(size.height, greaterThan(10));
          }
        },
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'dos prendas de calzado se escalonan con solape y llenan el alto de su franja',
    (tester) async {
      await _withTempPngs(
        tester,
        {
          // Mismo aspecto (1.5) que `s1` en los tests de arriba.
          'front': (width: 600, height: 400),
          'back': (width: 600, height: 400),
        },
        (paths) async {
          final front = _garment(
            'front',
            paths['front']!,
            GarmentCategory.calzado,
          );
          final back = _garment(
            'back',
            paths['back']!,
            GarmentCategory.calzado,
          );

          // Lienzo deliberadamente ancho: solo hay banda de calzado (sin
          // top/bottom compitiendo por alto), y el ancho sobra para que el
          // FittedBox(scaleDown) exterior no necesite reescalar el par ya
          // reducido por el solape — así se pueden afirmar números
          // concretos en vez de solo "no lanza excepción".
          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(garments: [front, back]),
              width: 900,
              height: 300,
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 2);

          expect(tester.takeException(), isNull);
          final images = find.byType(Image);
          expect(images, findsNWidgets(2));

          // Orden de pintado en _StaggeredFootwearPair: trasera (índice 0,
          // detrás) luego delantera (índice 1, encima).
          final backRect = tester.getRect(images.at(0));
          final frontRect = tester.getRect(images.at(1));

          // Se solapan horizontalmente — a diferencia del test de arriba
          // para 2 prendas de la banda "top", que exige NO solape. Aquí es
          // exactamente el comportamiento buscado.
          final overlaps =
              frontRect.left < backRect.right &&
              backRect.left < frontRect.right;
          expect(overlaps, isTrue);

          // La delantera llena (casi) el alto disponible de la franja, a
          // diferencia del Row lado a lado, que la limitaba por ancho.
          const bandHeight =
              300 - 2 * 16.0; // harness height - 2*gap por defecto
          expect(frontRect.height, greaterThan(bandHeight * 0.9));
        },
      );
    },
    timeout: _fastFail,
  );

  testWidgets(
    'tres prendas de calzado no se escalonan: cae al Row centrado sin overflow',
    (tester) async {
      final specs = {
        for (final n in ['s1', 's2', 's3']) n: (width: 600, height: 400),
      };
      await _withTempPngs(tester, specs, (paths) async {
        final shoes = [
          for (final n in ['s1', 's2', 's3'])
            _garment(n, paths[n]!, GarmentCategory.calzado),
        ];

        await tester.pumpWidget(
          _harness(OutfitFlatLayView(garments: shoes), width: 320, height: 300),
        );
        await _pumpUntilDecoded(tester, expectedImages: 3);

        expect(tester.takeException(), isNull);
        final images = find.byType(Image);
        expect(images, findsNWidgets(3));

        final rects = [
          for (var i = 0; i < 3; i++) tester.getRect(images.at(i)),
        ];
        for (var i = 0; i < rects.length - 1; i++) {
          final noOverlap =
              rects[i].right <= rects[i + 1].left ||
              rects[i + 1].right <= rects[i].left;
          expect(noOverlap, isTrue);
        }
      });
    },
    timeout: _fastFail,
  );

  testWidgets('una sola prenda de calzado no activa el escalonado', (
    tester,
  ) async {
    await _withTempPngs(tester, {'s1': (width: 600, height: 400)}, (
      paths,
    ) async {
      final shoe = _garment('s1', paths['s1']!, GarmentCategory.calzado);

      await tester.pumpWidget(_harness(OutfitFlatLayView(garments: [shoe])));
      await _pumpUntilDecoded(tester, expectedImages: 1);

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
    });
  }, timeout: _fastFail);

  testWidgets(
    'si falla el recorte de una de las dos prendas de calzado, cae al Row de siempre',
    (tester) async {
      await _withTempPngs(tester, {'good': (width: 600, height: 400)}, (
        paths,
      ) async {
        late String badPath;
        await tester.runAsync(() async {
          final dir = Directory(paths['good']!).parent;
          final badFile = File('${dir.path}/bad.png');
          // Bytes deliberadamente inválidos como PNG: fuerza el mismo fallo
          // de decodificación que dispara `snapshot.hasError` en
          // `_StaggeredFootwearPair` (vía `autocropGarment` dentro de
          // `GarmentAutocropCache.cropped`).
          await badFile.writeAsBytes([1, 2, 3, 4, 5]);
          badPath = badFile.path;
        });

        final good = _garment('good', paths['good']!, GarmentCategory.calzado);
        final bad = _garment('bad', badPath, GarmentCategory.calzado);

        await tester.pumpWidget(
          _harness(OutfitFlatLayView(garments: [good, bad])),
        );
        await _pumpUntilDecoded(tester, expectedImages: 2);

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsNWidgets(2));
      });
    },
    timeout: _fastFail,
  );

  group('OutfitFlatLayLayout.collage', () {
    testWidgets(
      'da al calzado más presencia que el reparto por franjas',
      (tester) async {
        // Proporciones reales del armario del usuario: la camiseta y el
        // pantalón son más altos que anchos, el par de zapatillas es ancho
        // y bajo — el caso exacto que el reparto por alto penalizaba.
        const specs = {
          't1': (width: 850, height: 1000),
          'b1': (width: 700, height: 1000),
          's1': (width: 1800, height: 1000),
        };

        await _withTempPngs(tester, specs, (paths) async {
          final garments = [
            _garment('t1', paths['t1']!, GarmentCategory.camiseta),
            _garment('b1', paths['b1']!, GarmentCategory.pantalon),
            _garment('s1', paths['s1']!, GarmentCategory.calzado),
          ];

          await tester.pumpWidget(
            _harness(OutfitFlatLayView(garments: garments)),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);
          final bandsShoe = tester.getRect(find.byType(Image).at(2));

          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(
                garments: garments,
                layout: OutfitFlatLayLayout.collage,
              ),
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);

          expect(tester.takeException(), isNull);
          expect(find.byType(Image), findsNWidgets(3));

          // El calzado es el último `Image` en ambos layouts (su franja va
          // la última y en el collage se pinta tras su sombra de contacto).
          final collageShoe = tester.getRect(find.byType(Image).at(2));

          // La razón de ser de este layout: el calzado ocupa MÁS área que
          // con las franjas. Se compara área y no solo alto porque el
          // collage también le da ancho real, que es de donde sale la
          // presencia visual de una prenda ancha-y-baja.
          final bandsArea = bandsShoe.width * bandsShoe.height;
          final collageArea = collageShoe.width * collageShoe.height;
          expect(collageArea, greaterThan(bandsArea));
        });
      },
      timeout: _fastFail,
    );

    testWidgets(
      'nunca desborda su lienzo, ni con muchas prendas ni en uno estrecho',
      (tester) async {
        final specs = {
          for (var i = 0; i < 6; i++) 'g$i': (width: 900, height: 700),
        };

        await _withTempPngs(tester, specs, (paths) async {
          // Mezcla deliberada: 2 superiores, 2 inferiores y 2 de calzado, es
          // decir varias prendas por categoría a la vez.
          const categories = [
            GarmentCategory.camiseta,
            GarmentCategory.chaqueta,
            GarmentCategory.pantalon,
            GarmentCategory.pantalon,
            GarmentCategory.calzado,
            GarmentCategory.calzado,
          ];
          final garments = [
            for (var i = 0; i < 6; i++)
              _garment('g$i', paths['g$i']!, categories[i]),
          ];

          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(
                garments: garments,
                layout: OutfitFlatLayLayout.collage,
              ),
              width: 180,
              height: 220,
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 6);

          expect(tester.takeException(), isNull);

          // El `FittedBox(contain)` que envuelve la escena es lo que da esta
          // garantía: se comprueba de verdad, no se da por supuesta.
          final canvas = tester.getRect(find.byType(OutfitFlatLayView));
          for (var i = 0; i < 6; i++) {
            final piece = tester.getRect(find.byType(Image).at(i));
            expect(piece.left, greaterThanOrEqualTo(canvas.left - 0.5));
            expect(piece.right, lessThanOrEqualTo(canvas.right + 0.5));
            expect(piece.top, greaterThanOrEqualTo(canvas.top - 0.5));
            expect(piece.bottom, lessThanOrEqualTo(canvas.bottom + 0.5));
          }
        });
      },
      timeout: _fastFail,
    );

    testWidgets(
      'con pocas prendas llena el hueco en vez de quedarse en una columna',
      (tester) async {
        // Con una prenda por categoría las filas salen estrechas y la escena
        // tiende a quedar más alta que ancha (aspecto natural ~0.6 con estas
        // prendas). El hueco de la hoja de detalle ya no es cuadrado sino
        // rectangular, con una forma parecida a esa, pero sigue sin ser
        // idéntica: el ajuste tiene que cerrar lo que falta.
        const specs = {
          't1': (width: 850, height: 1000),
          'b1': (width: 700, height: 1000),
          's1': (width: 1800, height: 1000),
        };

        await _withTempPngs(tester, specs, (paths) async {
          final garments = [
            _garment('t1', paths['t1']!, GarmentCategory.camiseta),
            _garment('b1', paths['b1']!, GarmentCategory.pantalon),
            _garment('s1', paths['s1']!, GarmentCategory.calzado),
          ];

          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(
                garments: garments,
                layout: OutfitFlatLayLayout.collage,
              ),
              // Proporción real del contenedor de `_OutfitDetailSheet` en un
              // móvil de gama media (ver `_kDetailCollageAspect` y
              // `_kDetailCollageMaxHeightFraction` en `outfit_screen.dart`).
              width: 363,
              height: 461,
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);

          expect(tester.takeException(), isNull);

          final container = tester.getRect(find.byType(OutfitFlatLayView));
          Rect? scene;
          for (var i = 0; i < 3; i++) {
            final piece = tester.getRect(find.byType(Image).at(i));
            scene = scene == null ? piece : scene.expandToInclude(piece);
          }

          // El alto ya se aprovechaba antes; lo que se desperdiciaba era el
          // ANCHO (llegaba al 48% contra el hueco cuadrado anterior). Medido
          // aquí: 89% de ancho y 90% de alto. Se exige 0.80 para que una
          // regresión al reparto anterior — o bajar de más los topes de
          // solape/desplazamiento — haga fallar el test, sin que un cambio
          // menor de proporciones lo rompa por unos píxeles.
          expect(scene!.width / container.width, greaterThan(0.80));
          expect(scene.height / container.height, greaterThan(0.80));
        });
      },
      timeout: _fastFail,
    );

    testWidgets('en un hueco estrecho y alto no se ensancha de más', (
      tester,
    ) async {
      // La otra cara del ajuste: si el hueco ya es MÁS estrecho que la
      // escena natural, separar las categorías o solaparlas no ayudaría
      // (el ancho es el lado que limita), así que debe dejarlo estar. Sin
      // esta rama, ensanchar a ciegas encogería las prendas.
      const specs = {
        't1': (width: 850, height: 1000),
        'b1': (width: 700, height: 1000),
        's1': (width: 1800, height: 1000),
      };

      await _withTempPngs(tester, specs, (paths) async {
        final garments = [
          _garment('t1', paths['t1']!, GarmentCategory.camiseta),
          _garment('b1', paths['b1']!, GarmentCategory.pantalon),
          _garment('s1', paths['s1']!, GarmentCategory.calzado),
        ];

        await tester.pumpWidget(
          _harness(
            OutfitFlatLayView(
              garments: garments,
              layout: OutfitFlatLayLayout.collage,
            ),
            width: 150,
            height: 400,
          ),
        );
        await _pumpUntilDecoded(tester, expectedImages: 3);

        expect(tester.takeException(), isNull);

        final container = tester.getRect(find.byType(OutfitFlatLayView));
        Rect? scene;
        for (var i = 0; i < 3; i++) {
          final piece = tester.getRect(find.byType(Image).at(i));
          scene = scene == null ? piece : scene.expandToInclude(piece);
        }

        // Aquí manda el ancho: la escena debe apurarlo y seguir cabiendo.
        expect(scene!.width / container.width, greaterThan(0.7));
        expect(scene.width, lessThanOrEqualTo(container.width + 0.5));
        expect(scene.height, lessThanOrEqualTo(container.height + 0.5));
      });
    }, timeout: _fastFail);

    testWidgets('una sola prenda también se compone sin excepción', (
      tester,
    ) async {
      await _withTempPngs(tester, {'only': (width: 600, height: 800)}, (
        paths,
      ) async {
        final single = _garment(
          'only',
          paths['only']!,
          GarmentCategory.camiseta,
        );

        await tester.pumpWidget(
          _harness(
            OutfitFlatLayView(
              garments: [single],
              layout: OutfitFlatLayLayout.collage,
            ),
          ),
        );
        await _pumpUntilDecoded(tester, expectedImages: 1);

        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
      });
    }, timeout: _fastFail);

    testWidgets(
      'si falla el recorte de una prenda, cae al layout de franjas',
      (tester) async {
        await _withTempPngs(tester, {
          'good': (width: 600, height: 800),
          'shoe': (width: 1800, height: 1000),
        }, (paths) async {
          late String badPath;
          await tester.runAsync(() async {
            final dir = Directory(paths['good']!).parent;
            final badFile = File('${dir.path}/bad.png');
            await badFile.writeAsBytes([1, 2, 3, 4, 5]);
            badPath = badFile.path;
          });

          final good = _garment(
            'good',
            paths['good']!,
            GarmentCategory.camiseta,
          );
          final bad = _garment('bad', badPath, GarmentCategory.pantalon);
          final shoe = _garment('shoe', paths['shoe']!, GarmentCategory.calzado);

          await tester.pumpWidget(
            _harness(
              OutfitFlatLayView(
                garments: [good, bad, shoe],
                layout: OutfitFlatLayLayout.collage,
              ),
            ),
          );
          await _pumpUntilDecoded(tester, expectedImages: 3);

          // Sin los datos de TODAS las prendas no hay escena que componer,
          // así que se pintan las franjas de siempre: las tres prendas
          // siguen viéndose (la fallida vía su respaldo sin recortar).
          expect(tester.takeException(), isNull);
          expect(find.byType(Image), findsNWidgets(3));
        });
      },
      timeout: _fastFail,
    );
  });
}
