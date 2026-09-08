import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

/// Recorta el fondo de la foto de una prenda con U2-Netp (NathanUA/U2-Net,
/// licencia Apache-2.0 — modelo y peso 100% libres para uso comercial),
/// ejecutado 100% en el dispositivo con ONNX Runtime. El modelo viaja dentro
/// de la app (`assets/models/u2netp.onnx`, ~4,6 MB — la exportación ONNX
/// oficial distribuida por el proyecto open-source `rembg`,
/// https://github.com/danielgatis/rembg): funciona igual en todas las
/// plataformas con soporte FFI, sin descargas diferidas ni diferencias entre
/// Android e iOS, y entrega máscaras con alfa continuo, mucho mejores para
/// tirantes, encajes o zonas semitransparentes que una segmentación binaria.
/// No hay red, clave de API ni coste.
///
/// Todo el trabajo pesado —cargar el modelo, preprocesar, inferir y aplicar
/// la máscara sobre la foto original— ocurre en un isolate dedicado y
/// persistente ([_U2NetWorker]): la sesión de ONNX Runtime es un puntero
/// nativo que no puede viajar en un `compute()`, y mantenerla viva evita
/// repetir la carga del modelo (varios segundos) en cada foto.
///
/// Web no está soportado (ONNX Runtime se integra aquí como plugin FFI); en
/// ese caso [removeBackground] lanza y el llamador conserva la foto mejorada
/// sin recortar.
class U2NetSegmentationService {
  /// Ruta del modelo tal y como está declarada en `pubspec.yaml`.
  static const String modelAsset = 'assets/models/u2netp.onnx';

  /// Resolución de entrada fija del modelo: `input` es `[batch, 3, 320, 320]`.
  static const int inputSize = 320;

  /// Tope de lado largo para la foto ANTES de decodificar/procesar nada.
  /// `AddGarmentScreen` ya se lo pide a `image_picker` (`maxWidth`/`maxHeight`
  /// al elegir foto), pero eso no cubre todos los orígenes posibles de
  /// [removeBackground] (por ejemplo una foto ya guardada a resolución
  /// completa): sin este tope, decodificar/reescalar la máscara/aplicar el
  /// alfa a resolución de cámara (12+ MP) puede tardar varios segundos por
  /// sí solo, muy por encima del coste de la propia inferencia.
  static const int maxLongEdge = 2048;

  /// Nombre del modelo ya extraído a disco. Lleva sufijo de versión para que,
  /// si algún día se sustituye el .onnx del bundle, el archivo cacheado no se
  /// reutilice por error: basta con subir el sufijo.
  static const String _cachedModelFileName = 'u2netp.v1.onnx';

  /// Tiempo máximo por foto. La primera inferencia incluye extraer el modelo
  /// a disco y cargarlo en ONNX Runtime, de ahí el margen amplio.
  static const Duration _timeout = Duration(seconds: 90);

  /// ONNX Runtime se integra como plugin FFI: hay binarios nativos para móvil
  /// y escritorio, pero no para web.
  static bool get isSupported =>
      !kIsWeb &&
      (io.Platform.isAndroid ||
          io.Platform.isIOS ||
          io.Platform.isMacOS ||
          io.Platform.isWindows ||
          io.Platform.isLinux);

  static _U2NetWorker? _worker;
  static Future<_U2NetWorker>? _starting;

  /// Arranca el isolate y carga el modelo por adelantado, sin procesar
  /// ninguna foto. Es opcional —[removeBackground] lo hace solo si hace
  /// falta—, pero llamarlo al abrir la pantalla de "Añadir prenda" hace que
  /// el modelo ya esté caliente cuando el usuario elige la foto.
  ///
  /// Nunca lanza: si la precarga falla, se registra y se reintentará en la
  /// primera llamada real a [removeBackground].
  static Future<void> prepare() async {
    if (!isSupported) return;
    try {
      await _obtainWorker();
    } catch (e, stackTrace) {
      debugPrint('[U2NetSegmentationService] No se pudo precargar U2-Netp: $e\n$stackTrace');
    }
  }

  /// Recibe los bytes de una foto y devuelve un PNG RGBA del MISMO tamaño con
  /// el fondo transparente. Lanza si la plataforma no está soportada, si el
  /// modelo no se puede cargar o si la máscara sale vacía (no se reconoció
  /// ninguna prenda), para que el llamador aplique su respaldo.
  static Future<Uint8List> removeBackground(Uint8List imageBytes) async {
    if (!isSupported) {
      throw Exception('El recorte con U2-Netp no está disponible en esta plataforma.');
    }

    final worker = await _obtainWorker();
    final stopwatch = Stopwatch()..start();
    final cutout = await worker.segment(imageBytes).timeout(
          _timeout,
          onTimeout: () => throw Exception(
            'U2-Netp tardó más de ${_timeout.inSeconds}s en recortar la prenda',
          ),
        );

    debugPrint(
      '[U2NetSegmentationService] Fondo eliminado con U2-Netp en '
      '${stopwatch.elapsedMilliseconds} ms',
    );
    return cutout;
  }

  /// Libera el isolate y la sesión de ONNX Runtime, que retiene el modelo en
  /// memoria. La siguiente llamada vuelve a arrancarlos.
  ///
  /// Si hay un arranque a medias ([_starting]) todavía no ha asignado
  /// [_worker], así que se espera a que termine antes de cerrarlo: sin esto,
  /// un `dispose()` disparado justo tras `prepare()` (p. ej. al abrir la
  /// cámara desde `add_garment_screen.dart`) dejaría vivo un isolate huérfano
  /// con el modelo cargado, justo lo contrario de lo que se busca al liberar
  /// memoria antes de la captura.
  static Future<void> dispose() async {
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Si el arranque falló no hay worker que cerrar.
      }
    }
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    await worker.shutdown();
  }

  /// Devuelve el worker listo, arrancándolo la primera vez. Si el isolate
  /// murió por su cuenta (error nativo fatal, falta de memoria...) se
  /// descarta y se arranca uno nuevo, en vez de encolar peticiones que solo
  /// acabarían en timeout. Varias fotos seguidas comparten un único arranque.
  static Future<_U2NetWorker> _obtainWorker() async {
    final ready = _worker;
    if (ready != null && ready.isAlive) return ready;

    final pending = _starting;
    if (pending != null) return pending;

    final started = _startWorker();
    _starting = started;
    try {
      final worker = await started;
      _worker = worker;
      return worker;
    } finally {
      if (identical(_starting, started)) _starting = null;
    }
  }

  static Future<_U2NetWorker> _startWorker() async {
    final modelPath = await _ensureModelOnDisk();
    return _U2NetWorker.spawn(modelPath);
  }

  /// ONNX Runtime necesita el modelo como archivo o como buffer en memoria, y
  /// los assets de Flutter viven comprimidos dentro del APK/IPA. Se copia una
  /// sola vez al directorio de soporte de la app y se reutiliza en arranques
  /// posteriores: así el isolate lo abre con `OrtSession.fromFile` sin mover
  /// varios MB por el puerto del isolate cada vez.
  static Future<String> _ensureModelOnDisk() async {
    final supportDir = await getApplicationSupportDirectory();
    final directory = io.Directory('${supportDir.path}/models');
    await directory.create(recursive: true);

    final file = io.File('${directory.path}/$_cachedModelFileName');
    if (await file.exists() && await file.length() > 0) return file.path;

    final data = await rootBundle.load(modelAsset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (bytes.isEmpty) {
      throw Exception('El modelo $modelAsset está vacío o no se pudo leer del bundle');
    }

    // Se escribe a un temporal y se renombra, para que una copia interrumpida
    // (sin espacio, app cerrada a medias...) no deje un .onnx truncado que el
    // siguiente arranque daría por válido.
    final partial = io.File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);

    debugPrint(
      '[U2NetSegmentationService] Modelo U2-Netp extraído a ${file.path} '
      '(${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)',
    );
    return file.path;
  }
}

// ---------------------------------------------------------------------------
// Isolate dedicado
// ---------------------------------------------------------------------------

/// Handle, en el isolate principal, del isolate que posee la sesión de ONNX
/// Runtime. Multiplexa varias peticiones sobre un único puerto con un id por
/// petición, así que es seguro llamar a [segment] mientras otra foto sigue
/// procesándose: se encolan en el worker.
class _U2NetWorker {
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final _pending = <int, Completer<Uint8List>>{};
  final _exited = Completer<void>();

  var _nextRequestId = 0;
  var _alive = true;

  /// `false` en cuanto el isolate termina, por cierre ordenado o por muerte
  /// inesperada. Un worker no vivo no debe reutilizarse.
  bool get isAlive => _alive;

  _U2NetWorker._(this._isolate, this._requests, this._responses) {
    _responses.listen(_onMessage);
  }

  static Future<_U2NetWorker> spawn(String modelPath) async {
    final handshake = ReceivePort();
    // El mismo puerto recibe los resultados, los errores no capturados del
    // isolate (`onError`) y su terminación (`onExit`), para poder fallar
    // rápido en vez de esperar al timeout si el worker se cae.
    final responses = ReceivePort();

    final isolate = await Isolate.spawn(
      _u2NetWorkerMain,
      _WorkerInit(handshake.sendPort, modelPath),
      debugName: 'U2NetSegmentationIsolate',
      errorsAreFatal: true,
      onError: responses.sendPort,
      onExit: responses.sendPort,
    );

    // El worker contesta con su SendPort si la sesión se creó, o con un
    // String describiendo el fallo (modelo corrupto, binario nativo ausente...).
    // El timeout cubre el caso en que el isolate muera antes de contestar:
    // sin él, este `await` no terminaría nunca y la pantalla se quedaría
    // colgada en "recortando prenda".
    final first = await handshake.first.timeout(
      const Duration(seconds: 60),
      onTimeout: () => 'el isolate no respondió al arrancar',
    );
    handshake.close();

    if (first is! SendPort) {
      responses.close();
      isolate.kill(priority: Isolate.immediate);
      throw Exception('No se pudo iniciar U2-Netp: $first');
    }

    // Los mensajes de un mismo puerto llegan en orden, así que el worker ya
    // tendrá este puerto registrado antes de recibir ninguna petición.
    first.send(responses.sendPort);
    return _U2NetWorker._(isolate, first, responses);
  }

  Future<Uint8List> segment(Uint8List imageBytes) {
    if (!_alive) {
      return Future.error(StateError('El worker de U2-Netp ya no está activo'));
    }

    final id = _nextRequestId++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    // Los bytes de entrada se envían tal cual (copia): el llamador sigue
    // usando ese mismo Uint8List en paralelo para mejorar la foto, y
    // `TransferableTypedData` lo dejaría inutilizable al transferirlo.
    _requests.send(_SegmentRequest(id, imageBytes));
    return completer.future;
  }

  void _onMessage(dynamic message) {
    // Puerto onExit: el isolate ha terminado.
    if (message == null) {
      if (!_exited.isCompleted) _exited.complete();
      _handleDeath('el isolate de U2-Netp terminó inesperadamente');
      return;
    }
    // Puerto onError: [descripción del error, stack trace].
    if (message is List) {
      _handleDeath('U2-Netp falló en su isolate: ${message.first}');
      return;
    }

    final response = message as _SegmentResponse;
    final completer = _pending.remove(response.id);
    if (completer == null || completer.isCompleted) return;

    final cutout = response.cutout;
    if (cutout == null) {
      completer.completeError(Exception(response.error ?? 'Error desconocido en U2-Netp'));
    } else {
      completer.complete(cutout.materialize().asUint8List());
    }
  }

  void _handleDeath(String reason) {
    if (!_alive) return;
    _alive = false;
    debugPrint('[U2NetSegmentationService] $reason');
    _failPending(reason);
    _responses.close();
  }

  /// Cierre ORDENADO: la sesión y el entorno de ONNX Runtime viven en memoria
  /// nativa, que matar el isolate no libera. Por eso se le pide al worker que
  /// termine solo (mensaje `null`) y se espera a que confirme su salida por
  /// el puerto `onExit`; matarlo queda como último recurso si se atasca.
  Future<void> shutdown() async {
    if (!_alive) return;
    _alive = false;
    _failPending('el worker de U2-Netp se cerró');

    // Se encola detrás de la foto que estuviera procesándose, así que el
    // margen contempla terminarla antes de liberar.
    _requests.send(null);
    await _exited.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(
          '[U2NetSegmentationService] El worker no cerró a tiempo; se fuerza '
          'la terminación del isolate',
        );
        _isolate.kill(priority: Isolate.beforeNextEvent);
      },
    );
    _responses.close();
  }

  void _failPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(Exception(reason));
    }
    _pending.clear();
  }
}

/// Mensaje de arranque del isolate.
class _WorkerInit {
  final SendPort handshake;
  final String modelPath;

  const _WorkerInit(this.handshake, this.modelPath);
}

class _SegmentRequest {
  final int id;
  final Uint8List imageBytes;

  const _SegmentRequest(this.id, this.imageBytes);
}

class _SegmentResponse {
  final int id;

  /// PNG RGBA con el fondo transparente, o `null` si hubo error. Viaja como
  /// [TransferableTypedData] —se mueve sin copiar— porque un recorte a
  /// resolución completa son decenas de MB y el worker ya no lo necesita.
  final TransferableTypedData? cutout;
  final String? error;

  const _SegmentResponse(this.id, this.cutout, this.error);
}

/// Punto de entrada del isolate: crea la sesión de ONNX Runtime una sola vez
/// y atiende peticiones hasta recibir `null` como señal de cierre.
///
/// `OrtEnv` es un singleton por isolate y el entorno nativo de ONNX Runtime
/// debe existir una única vez en el proceso: por eso se inicializa AQUÍ y
/// nunca en el isolate principal.
Future<void> _u2NetWorkerMain(_WorkerInit init) async {
  final OrtSessionOptions sessionOptions;
  final OrtSession session;
  try {
    OrtEnv.instance.init(level: OrtLoggingLevel.error, logId: 'U2NetSegmentation');
    sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(_intraOpThreads())
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    // En Windows, OrtSession.fromFile codifica la ruta en UTF-8, pero la
    // CreateSession nativa de onnxruntime ahí espera wchar_t* (ORTCHAR_T es
    // char en Android/iOS/macOS, pero wchar_t en Windows): con fromFile el
    // path llega corrupto y la carga falla con "File doesn't exist". Se evita
    // por completo leyendo el archivo y pasando los bytes con fromBuffer,
    // solo en Windows; en el resto de plataformas se mantiene fromFile
    // (mapea el archivo en vez de copiar el modelo entero al heap).
    session = io.Platform.isWindows
        ? OrtSession.fromBuffer(await io.File(init.modelPath).readAsBytes(), sessionOptions)
        : OrtSession.fromFile(io.File(init.modelPath), sessionOptions);
  } catch (e) {
    init.handshake.send('no se pudo cargar el modelo ONNX: $e');
    return;
  }

  final requests = ReceivePort();
  init.handshake.send(requests.sendPort);

  // El isolate principal contesta con el puerto por el que quiere recibir los
  // resultados; hasta entonces no hay a dónde responder.
  SendPort? responses;

  await for (final message in requests) {
    if (message is SendPort) {
      responses ??= message;
      continue;
    }
    if (message == null) break;

    final request = message as _SegmentRequest;
    try {
      final cutout = _segment(session, request.imageBytes);
      responses?.send(
        _SegmentResponse(request.id, TransferableTypedData.fromList([cutout]), null),
      );
    } catch (e) {
      responses?.send(_SegmentResponse(request.id, null, '$e'));
    }
  }

  requests.close();
  session.release();
  sessionOptions.release();
  OrtEnv.instance.release();
}

/// Deja al menos un núcleo libre para la UI, con un techo de 4 hilos: por
/// encima, la ganancia en un modelo de este tamaño es marginal y el gasto de
/// batería no lo es.
int _intraOpThreads() {
  final cores = io.Platform.numberOfProcessors;
  final usable = cores <= 2 ? 1 : cores - 1;
  return usable > 4 ? 4 : usable;
}

// ---------------------------------------------------------------------------
// Pipeline de segmentación (siempre dentro del isolate)
// ---------------------------------------------------------------------------

/// Media/desviación de ImageNet (RGB) que usa el preprocesado de referencia
/// de U2-Net (`ToTensorLab` en el repo oficial NathanUA/U2-Net, y el mismo
/// `u2net.py` de `rembg` que exportó el .onnx del bundle): el modelo se
/// entrenó con la entrada normalizada así, no con `pixel/255`.
const _imageNetMean = [0.485, 0.456, 0.406];
const _imageNetStd = [0.229, 0.224, 0.225];

/// Preprocesa la foto, ejecuta U2-Netp y devuelve un PNG RGBA con el fondo
/// transparente, a la resolución original (o capada a [maxLongEdge] si la
/// excedía: ver [_capResolution]).
Uint8List _segment(OrtSession session, Uint8List imageBytes) {
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) {
    throw Exception('No se pudo decodificar la foto de la prenda');
  }

  final original = _capResolution(decoded);
  final mask = _runModel(session, _preprocess(original));
  return applyMask(original, mask);
}

/// Reescala la foto para que su lado largo no supere
/// [U2NetSegmentationService.maxLongEdge], si hace falta. `applyMask`
/// reescala la máscara y aplica el alfa a la resolución de ESTA imagen, así
/// que caparla aquí es lo que evita pagar esos pasos (y `encodePng` final) a
/// resolución de cámara.
img.Image _capResolution(img.Image image) {
  const maxEdge = U2NetSegmentationService.maxLongEdge;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge <= maxEdge) return image;

  final scale = maxEdge / longEdge;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// Convierte la foto en el tensor que espera U2-Netp: RGB en formato CHW,
/// reescalado a 320x320 (deformando la relación de aspecto, igual que el
/// preprocesado de referencia del modelo) y normalizado con media/desviación
/// de ImageNet por canal (ver [_imageNetMean]/[_imageNetStd]).
Float32List _preprocess(img.Image original) {
  const size = U2NetSegmentationService.inputSize;
  const plane = size * size;

  final resized = img.copyResize(
    original,
    width: size,
    height: size,
    interpolation: img.Interpolation.linear,
  );

  final tensor = Float32List(3 * plane);
  // Se reutiliza el mismo objeto Pixel en todo el recorrido: `getPixel` crea
  // uno nuevo por llamada si no se le pasa, y aquí son cientos de miles de
  // llamadas.
  final pixel = resized.getPixel(0, 0);
  var i = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      resized.getPixel(x, y, pixel);
      tensor[i] = (pixel.r / 255.0 - _imageNetMean[0]) / _imageNetStd[0];
      tensor[plane + i] = (pixel.g / 255.0 - _imageNetMean[1]) / _imageNetStd[1];
      tensor[2 * plane + i] = (pixel.b / 255.0 - _imageNetMean[2]) / _imageNetStd[2];
      i++;
    }
  }
  return tensor;
}

/// Ejecuta la inferencia y devuelve la máscara ya normalizada. Los `OrtValue`
/// envuelven memoria nativa que el recolector de Dart no gestiona, así que se
/// liberan siempre, también si la inferencia falla.
Float32List _runModel(OrtSession session, Float32List input) {
  const size = U2NetSegmentationService.inputSize;

  final inputTensor = OrtValueTensor.createTensorWithDataList(input, [1, 3, size, size]);
  final runOptions = OrtRunOptions();
  List<OrtValue?>? outputs;
  try {
    // U2-Net(p) expone 7 salidas (`d0`..`d6`, una por etapa del decodificador
    // "side output"); `d0` —la fusión final, mejor calidad— es SIEMPRE la
    // primera en `graph.output` en el export oficial y en el de `rembg`, así
    // que basta con pedir la primera salida del grafo (igual que hace
    // `rembg` internamente: `ort_outs[0]`). Se usa el nombre real del grafo
    // en vez de un literal, por si el modelo se regenera con otro nombre.
    outputs = session.run(
      runOptions,
      {session.inputNames.first: inputTensor},
      [session.outputNames.first],
    );
    return _extractMask(outputs);
  } finally {
    outputs?.forEach((value) => value?.release());
    inputTensor.release();
    runOptions.release();
  }
}

/// Extrae el mapa de confianza de la salida del modelo y lo normaliza a
/// `[0, 1]` por min-max, como el postprocesado de referencia de U2-Net: la
/// sigmoide de salida rara vez satura, y sin ese reescalado los bordes quedan
/// grises y la prenda entera semitransparente.
Float32List _extractMask(List<OrtValue?> outputs) {
  const expected =
      U2NetSegmentationService.inputSize * U2NetSegmentationService.inputSize;

  if (outputs.isEmpty || outputs.first == null) {
    throw Exception('U2-Netp no devolvió ninguna salida');
  }

  // `value` llega como listas anidadas con la forma real del tensor
  // (`[1, 1, 320, 320]`). Si un export futuro devolviera varios mapas
  // apilados, los primeros `expected` valores siguen siendo el principal.
  final mask = Float32List(expected);
  var count = 0;
  void collect(Object? node) {
    if (count >= expected) return;
    if (node is num) {
      mask[count++] = node.toDouble();
      return;
    }
    if (node is List) {
      for (final child in node) {
        if (count >= expected) return;
        collect(child);
      }
      return;
    }
    throw Exception('Salida inesperada de U2-Netp: ${node.runtimeType}');
  }

  collect(outputs.first!.value);
  if (count < expected) {
    throw Exception(
      'U2-Netp devolvió una máscara incompleta ($count de $expected valores)',
    );
  }

  var min = double.infinity;
  var max = -double.infinity;
  for (final value in mask) {
    if (value < min) min = value;
    if (value > max) max = value;
  }

  // Máscara plana: el modelo no ha separado nada (fondo liso a pantalla
  // completa, primerísimo plano...). Normalizar aquí solo amplificaría ruido,
  // así que se trata como "sin prenda reconocida".
  final range = max - min;
  if (range < 1e-6) {
    throw Exception('U2-Netp no encontró ninguna prenda en la foto');
  }

  for (var i = 0; i < expected; i++) {
    mask[i] = (mask[i] - min) / range;
  }
  return mask;
}

/// Aplica la máscara como canal alfa sobre la foto ORIGINAL a resolución
/// completa: la máscara se reescala de 320x320 al tamaño real con
/// interpolación lineal, igual que el postprocesado de referencia, para que
/// el borde del recorte quede suave en vez de dentado.
///
/// Pública (no top-level privada) a propósito, igual que [autocropGarment]
/// en `garment_autocrop_service.dart`: no depende de nada del isolate ni de
/// ONNX Runtime (solo recibe la máscara ya calculada), así que un test puede
/// construir una `img.Image` y un `Float32List` sintéticos y llamarla
/// directamente, sin necesidad de correr el modelo de verdad.
Uint8List applyMask(img.Image original, Float32List mask) {
  const size = U2NetSegmentationService.inputSize;

  final maskImage = img.Image(width: size, height: size, numChannels: 1);
  for (var y = 0; y < size; y++) {
    final row = y * size;
    for (var x = 0; x < size; x++) {
      maskImage.setPixelR(x, y, (mask[row + x] * 255).round().clamp(0, 255));
    }
  }

  final scaledMask = (maskImage.width == original.width && maskImage.height == original.height)
      ? maskImage
      : img.copyResize(
          maskImage,
          width: original.width,
          height: original.height,
          interpolation: img.Interpolation.linear,
        );

  final cutout = img.Image(width: original.width, height: original.height, numChannels: 4);
  final sourcePixel = original.getPixel(0, 0);
  final maskPixel = scaledMask.getPixel(0, 0);
  var opaque = 0;
  for (var y = 0; y < original.height; y++) {
    for (var x = 0; x < original.width; x++) {
      final alpha = scaledMask.getPixel(x, y, maskPixel).r.toInt();
      // El lienzo nace transparente, así que los píxeles de fondo se saltan.
      if (alpha <= 0) continue;
      if (alpha > 127) opaque++;
      original.getPixel(x, y, sourcePixel);
      cutout.setPixelRgba(x, y, sourcePixel.r, sourcePixel.g, sourcePixel.b, alpha);
    }
  }

  // Recorte residual (menos del 1% de la foto): en la práctica es ruido, no
  // una prenda. Mejor fallar y dejar que el llamador use su respaldo que
  // guardar una imagen casi vacía.
  if (opaque < original.width * original.height * 0.01) {
    throw Exception('U2-Netp no encontró ninguna prenda en la foto');
  }

  // Guarda simétrica de la anterior: la máscara marcó como opaco el 95% o
  // más de la foto. La normalización min-max de _extractMask siempre estira
  // la salida del modelo a 0..1 en cuanto hay algo de rango, así que una
  // separación de confianza floja (fondos reales con textura —sábana,
  // suelo de madera— en vez de los fondos lisos de estudio del modelo)
  // puede colar una máscara "válida" que en realidad no aisló nada: el
  // resultado es la foto entera sin recortar, disfrazada de recorte. Mejor
  // fallar aquí y dejar que el llamador conserve la foto mejorada sin
  // recortar que persistir eso.
  if (opaque > original.width * original.height * 0.95) {
    throw Exception('U2-Netp no logró separar la prenda del fondo en la foto');
  }

  return Uint8List.fromList(img.encodePng(cutout));
}
