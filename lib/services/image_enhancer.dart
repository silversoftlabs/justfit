import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Kernel de convolución de enfoque (sharpen) 3x3 estándar: acentúa bordes
/// y costuras sin introducir artefactos agresivos.
const _sharpenKernel = <num>[
  0, -1, 0,
  -1, 5, -1,
  0, -1, 0,
];

/// Aplica una mejora automática de calidad (contraste, brillo y enfoque) a
/// una foto escaneada de una prenda.
///
/// Es una función top-level pura (sin estado de widget) a propósito: es el
/// requisito de `compute()` para poder ejecutarla en un isolate secundario y
/// así no bloquear la UI mientras se decodifica/recodifica la imagen.
Uint8List enhanceGarmentPhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final adjusted = img.adjustColor(
    decoded,
    contrast: 1.12,
    brightness: 1.05,
  );
  final sharpened = img.convolution(adjusted, filter: _sharpenKernel);

  return Uint8List.fromList(img.encodePng(sharpened));
}
