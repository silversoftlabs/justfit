import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        compute,
        debugPrint,
        defaultTargetPlatform,
        kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/garment.dart';
import '../models/garment_options.dart';
import '../models/tipo_prenda.dart';
import '../providers/wardrobe_provider.dart';
import 'camera_capture_screen.dart';
import 'crop_edit_screen.dart';
import '../services/color_extraction_service.dart';
import '../services/image_compositor.dart';
import '../services/image_enhancer.dart';
import '../services/image_storage.dart';
import '../services/u2net_segmentation_service.dart';
import '../theme/app_palette.dart';
import '../theme/ios_design.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/garment_image.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/selector_prenda_widget.dart';
import '../widgets/shimmer_box.dart';

class AddGarmentScreen extends StatefulWidget {
  /// Foto que `image_picker` había dejado en `retrieveLostData` porque Android
  /// mató el proceso con la cámara abierta, recuperada por
  /// `HomeScreen._recoverAbandonedCaptureIfAny` (única red de seguridad para
  /// ese caso: al morir el proceso esta pantalla desaparece del árbol y su
  /// propia recuperación ya no puede ejecutarse). Cuando llega, la pantalla
  /// arranca analizándola directamente en vez de mostrar el formulario vacío.
  final XFile? recoveredImage;

  const AddGarmentScreen({super.key, this.recoveredImage});

  /// `true` mientras hay una instancia de esta pantalla montada. Lo consulta
  /// `HomeScreen` para NO duplicar la recuperación de `retrieveLostData`: si
  /// esta pantalla sigue viva (el proceso no llegó a morir), su propio
  /// [_AddGarmentScreenState._recoverLostImageIfAny] ya se encarga y además
  /// conserva el formulario a medio rellenar.
  static bool isOpen = false;

  @override
  State<AddGarmentScreen> createState() => _AddGarmentScreenState();
}

class _AddGarmentScreenState extends State<AddGarmentScreen> with WidgetsBindingObserver {
  final _picker = ImagePicker();

  String? _pickedImagePath;

  // Rellenado automaticamente midiendo los pixeles del recorte. Null
  // mientras se calcula, para que la tarjeta muestre el shimmer en vez de
  // un valor provisional que parezca definitivo.
  String? _color;

  /// Color exacto medido en la foto (0xRRGGBB), para pintar la muestra junto
  /// al nombre. Null si el calculo fallo o aun no ha terminado.
  int? _colorSwatch;

  // Los elige el usuario: NO se inicializan. Un valor por defecto aqui se
  // leeria como una sugerencia ya hecha por la IA, que es justo lo que hay
  // que evitar.
  TipoPrenda? _tipoPrenda;
  GarmentStyle? _style;
  GarmentSeason? _season;

  bool _isFavorite = false;
  bool _saving = false;
  bool _processingImage = false;

  /// `true` cuando el análisis automático (mejora + recorte + color) falló
  /// para la foto actual. La foto sigue cargada y el formulario pasa a
  /// "edición manual": el usuario elige el color a mano y puede guardar la
  /// prenda igualmente. Se reinicia con cada foto nueva (ver [_beginAnalysis]).
  bool _autoAnalysisFailed = false;

  /// Precarga del isolate de ONNX Runtime lanzada en [initState]. Tras una
  /// recreación del proceso ese isolate arranca de cero; [_removeBackgroundSafe]
  /// espera a este `Future` antes de pedir la inferencia, para no competir con
  /// la precarga por el primer arranque y asegurar que el modelo está listo.
  Future<void>? _segmentationWarmup;

  /// Mensaje único para cuando la foto llega a disco vacía o truncada — lo que
  /// deja `retrieveLostData` si el proceso murió a mitad de escribir la
  /// captura. `File.exists()` la da por buena, pero no tiene bytes que
  /// decodificar. El aviso lleva además un botón "Usar galería" (ver
  /// [_abortImageLoad]), la vía que no sufre este problema de memoria.
  static const _incompletePhotoMessage = 'La foto de la cámara llegó incompleta.';

  /// Texto de fase que se ve mientras `_processingImage` es true. Ver
  /// [_GarmentProcessingProgress]: no fabrica tiempos, solo reacciona a
  /// señales reales de `_processImage`.
  final _progress = _GarmentProcessingProgress();

  /// Faltan datos obligatorios que solo puede aportar el usuario. El tipo de
  /// complemento ya no es un campo aparte: viene fijado por [_tipoPrenda]
  /// (ver [TipoPrendaMapping.accessoryType] en `models/tipo_prenda.dart`).
  bool get _missingUserFields =>
      _tipoPrenda == null || _style == null || _season == null;

  /// Evita procesar dos veces la misma captura recuperada: `retrieveLostData`
  /// vacía su caché al leerla, pero `didChangeAppLifecycleState(resumed)`
  /// puede dispararse varias veces seguidas y una recuperación ya en curso no
  /// debe solaparse con otra.
  bool _recoveringLostImage = false;

  @override
  void initState() {
    super.initState();
    AddGarmentScreen.isOpen = true;
    WidgetsBinding.instance.addObserver(this);
    // Cargar U2-Netp en su isolate lleva unos segundos la primera vez. Se
    // lanza al abrir la pantalla, en paralelo a que el usuario elija la foto,
    // para que el modelo ya esté caliente al llegar a _processImage. Se guarda
    // el `Future` (no `unawaited`) porque `_removeBackgroundSafe` lo espera
    // antes de la inferencia — clave en la ruta de foto recuperada, donde el
    // análisis arranca solo, sin la pausa de que el usuario encuadre la foto.
    _segmentationWarmup = U2NetSegmentationService.prepare();
    final recovered = widget.recoveredImage;
    if (recovered != null) {
      // Se llegó aquí porque el proceso murió con la cámara abierta y
      // `HomeScreen` reabrió esta pantalla con la foto ya capturada: se
      // retoma el análisis directamente, sin volver a abrir la cámara.
      unawaited(_beginAnalysis(recovered));
    } else {
      // En Android, lanzar la cámara puede hacer que el sistema mate el
      // proceso de Flutter por falta de memoria mientras el usuario encuadra
      // la foto. Al volver, `pickImage` de la instancia anterior ya no
      // resolverá nunca: la foto capturada queda como "dato perdido" que hay
      // que reclamar explícitamente (ver [_recoverLostImageIfAny]).
      unawaited(_recoverLostImageIfAny());
    }
  }

  @override
  void dispose() {
    AddGarmentScreen.isOpen = false;
    WidgetsBinding.instance.removeObserver(this);
    // La sesión de ONNX Runtime mantiene el modelo y sus arenas de trabajo en
    // memoria nativa, y esta pantalla es su único consumidor: al salir se
    // libera y se volverá a precargar en la siguiente visita.
    unawaited(U2NetSegmentationService.dispose());
    _progress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Al recuperar el foco tras la cámara (o tras una muerte del proceso en
    // segundo plano) se vuelve a comprobar si `image_picker` guardó una foto
    // que no llegó a entregarse. Si no hay nada pendiente, la llamada es un
    // no-op barato.
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverLostImageIfAny());
    }
  }

  /// Reclama a `image_picker` (solo Android) una foto que quedó sin entregar
  /// porque el sistema mató el proceso mientras la cámara estaba abierta. Sin
  /// esto, el usuario volvía a la pantalla —o directamente a Inicio— con el
  /// formulario vacío y sin forma de guardar la prenda que acababa de
  /// fotografiar. En iOS/Web/escritorio `retrieveLostData` devuelve siempre
  /// una respuesta vacía, así que este método no hace nada allí.
  /// Devuelve `true` si hubo algo que atender (una foto recuperada o un fallo
  /// real de recuperación ya notificado al usuario), y `false` si no había
  /// ninguna captura pendiente. `_pickImage` lo usa para decidir si aún tiene
  /// que mostrar el aviso de fallback tras un `pickImage` nulo.
  Future<bool> _recoverLostImageIfAny() async {
    if (_recoveringLostImage || _processingImage) return true;
    _recoveringLostImage = true;
    try {
      final LostDataResponse response = await _picker.retrieveLostData();
      // Respuesta vacía = no había ninguna captura en vuelo (caso normal en
      // cada `resumed`, y en iOS/Web/escritorio siempre): nada que hacer.
      if (response.isEmpty) return false;
      if (!mounted) return true;

      final file = response.file;
      if (file == null) {
        // Aquí SÍ había una captura en vuelo (la respuesta no venía vacía):
        // si `image_picker` no puede devolver el archivo, es un fallo real y
        // se avisa con las alternativas.
        debugPrint(
          '[AddGarmentScreen] retrieveLostData sin archivo: ${response.exception}',
        );
        _abortImageLoad(notify: true);
        return true;
      }

      await _beginAnalysis(file);
      return true;
    } finally {
      _recoveringLostImage = false;
    }
  }

  /// Arranca (o retoma) el análisis de una foto ya capturada: valida que el
  /// archivo siga en disco —`retrieveLostData` puede devolver una ruta que el
  /// sistema ya limpió al matar el proceso—, la fija como vista previa y llama
  /// a [_processImage]. Es la parte común entre la recuperación interna
  /// ([_recoverLostImageIfAny]) y la foto que llega ya recuperada desde
  /// `HomeScreen` ([AddGarmentScreen.recoveredImage]). Cualquier fallo del
  /// análisis lo gestiona [_processImage] en su propio `try/catch`, dejando al
  /// usuario en esta pantalla con la foto cargada y un aviso.
  Future<void> _beginAnalysis(XFile file) async {
    if (!await _capturedFileIsUsable(file)) {
      debugPrint(
        '[AddGarmentScreen] La foto a analizar no existe o está vacía: '
        '${file.path}',
      );
      _abortImageLoad(notify: true, message: _incompletePhotoMessage);
      return;
    }
    final previewPath = await _previewPathFor(file);
    if (!mounted) return;
    setState(() {
      _pickedImagePath = previewPath;
      // Al cambiar de foto se descarta el color medido de la anterior:
      // dejarlo visible mientras se recalcula haría creer que ya se ha
      // detectado sobre la foto nueva. El tipo de prenda, el estilo y la
      // temporada NO se tocan: son elecciones del usuario y no dependen de
      // la imagen.
      _color = null;
      _colorSwatch = null;
      // Foto nueva: el análisis empieza de cero, aún no ha fallado.
      _autoAnalysisFailed = false;
    });
    await _processImage(file, fallbackPath: previewPath);
  }

  String _extensionOf(XFile file) {
    final dot = file.name.lastIndexOf('.');
    if (dot == -1 || dot == file.name.length - 1) return 'jpg';
    return file.name.substring(dot + 1).toLowerCase();
  }

  /// Ruta de vista previa inmediata tras seleccionar la foto: en móvil se usa
  /// la ruta real que ya entrega image_picker; en Web (sin filesystem) se
  /// codifican los bytes como data URL para poder pintarla con Image.memory.
  Future<String> _previewPathFor(XFile file) async {
    if (!kIsWeb) return file.path;
    final bytes = await file.readAsBytes();
    return ImageStorage.persist(
      bytes,
      id: 'preview',
      extension: _extensionOf(file),
    );
  }

  /// Comprueba que la foto entregada por `image_picker` (o recuperada por
  /// `retrieveLostData`) apunte a un archivo que existe DE VERDAD en disco
  /// **y tiene contenido (> 0 bytes)** antes de arrancar el análisis.
  ///
  /// Las dos comprobaciones cubren fallos distintos de la muerte del proceso
  /// con la cámara abierta:
  ///  - archivo ausente: la ruta temporal de `image_picker` desapareció al
  ///    reiniciar → sin esta guarda `_processImage` se quedaba "analizando"
  ///    una foto fantasma.
  ///  - archivo de 0 bytes o truncado: el sistema mató el proceso a mitad de
  ///    escribir la captura. `exists()` lo da por bueno, pero `readAsBytes`
  ///    devuelve vacío y TODOS los decodificadores de abajo
  ///    (`enhanceGarmentPhoto`, U2-Netp, `renderSoftFallback`) fallan, disparando
  ///    el `catch` de `_processImage` ("No se pudo procesar la foto").
  ///
  /// En Web no hay filesystem: el `XFile` va respaldado por bytes en memoria,
  /// así que allí se asume utilizable y la validación se delega en
  /// `readAsBytes` dentro de `_processImage` (envuelto en su try/catch).
  Future<bool> _capturedFileIsUsable(XFile? file) async {
    if (file == null) return false;
    if (kIsWeb) return true;
    final path = file.path;
    if (path.isEmpty) return false;
    try {
      final f = File(path);
      return await f.exists() && await f.length() > 0;
    } catch (e) {
      debugPrint('[AddGarmentScreen] No se pudo comprobar la foto "$path": $e');
      return false;
    }
  }

  /// Deja la UI fuera de cualquier estado de carga y avisa al usuario cuando
  /// la foto capturada no llegó a materializarse (o llegó vacía/truncada).
  /// Centralizado para que `_pickFrom`, `_beginAnalysis`, `_processImage` y
  /// `_recoverLostImageIfAny` reaccionen igual. [message] permite un aviso
  /// específico según la causa; si es `null` se usa el genérico de la cámara.
  ///
  /// El aviso incluye un botón "Usar galería" que reabre el selector de fotos
  /// directamente en la galería (`_pickFrom(ImageSource.gallery)`): es la
  /// salida rápida cuando la cámara falla por memoria, ya que la galería no
  /// dispara ese pico. En Web no aplica (no hay este problema de proceso).
  void _abortImageLoad({required bool notify, String? message}) {
    _recoveringLostImage = false;
    _progress.stop();
    if (!mounted) {
      _processingImage = false;
      return;
    }
    setState(() => _processingImage = false);
    if (notify) {
      // Mensaje vía `ScaffoldMessenger` (AppSnackBar lo usa por dentro).
      AppSnackBar.show(
        context,
        message ?? 'No se pudo recuperar la foto de la cámara.',
        type: AppSnackBarType.error,
        duration: const Duration(seconds: 6),
        actionLabel: kIsWeb ? null : 'Usar galería',
        onAction: kIsWeb ? null : () => unawaited(_pickFrom(ImageSource.gallery)),
      );
    }
  }

  Future<void> _pickImage() async {
    final source = await showGlassSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Hacer foto'),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(context).pop(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );

    // Al llegar aquí el `showModalBottomSheet` ya se ha cerrado (su `Future`
    // solo resuelve tras hacer `pop`), así que la cámara/galería se abre sin
    // ninguna hoja por encima. `mounted` puede haber cambiado si el usuario
    // salió de la pantalla mientras la hoja estaba abierta.
    if (source == null || !mounted) return;
    await _pickFrom(source);
  }

  /// `true` en las plataformas donde usamos la cámara embebida
  /// ([CameraCaptureScreen]) en vez del intent de cámara del sistema: solo
  /// Android e iOS. En Web/escritorio se sigue delegando en `image_picker`.
  static bool get _useInAppCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Abre la cámara o la galería en la fuente indicada, recoge la foto y
  /// arranca el análisis. Separado de [_pickImage] para poder reutilizarlo
  /// como acción "Usar galería" del aviso de error (ver [_abortImageLoad]).
  Future<void> _pickFrom(ImageSource source) async {
    if (!mounted) return;
    final fromCamera = source == ImageSource.camera;

    if (fromCamera && _useInAppCamera) {
      await _captureWithInAppCamera();
      return;
    }

    if (fromCamera) {
      // Libera el modelo U2-Netp (+ las arenas nativas de ONNX Runtime)
      // ANTES de abrir la cámara nativa: es la tarea en segundo
      // plano más pesada de esta pantalla, y bajar la huella de RAM del
      // proceso reduce la probabilidad de que Android lo mate mientras la
      // cámara está en primer plano. `unawaited` a propósito: la limpieza no
      // debe retrasar la apertura de la cámara, y `dispose()` ya espera por
      // dentro a un arranque a medias antes de cerrar. Se vuelve a precargar
      // justo después de la captura.
      unawaited(U2NetSegmentationService.dispose());
    }

    // Topes de resolución/calidad ANTES de que la foto llegue a Dart: sin
    // ellos, la cámara del sistema entrega el JPEG a resolución nativa (12+
    // MP, decenas de MB en memoria sin comprimir), justo el pico de memoria
    // que hace que Android mate el proceso al volver de la cámara. 1080px de
    // lado largo va de sobra para el modelo de recorte (entra a 1024) y para
    // la vista de detalle; el downscale lo hace la plataforma nativa, más
    // barato que reescalar luego en Dart, y además acelera el guardado del
    // archivo a disco antes de que el sistema suspenda el proceso.
    XFile? xFile;
    try {
      xFile = await _picker.pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 85,
      );
    } catch (e, stackTrace) {
      debugPrint('[AddGarmentScreen] pickImage lanzó: $e\n$stackTrace');
    }

    if (fromCamera) {
      // Rearranca la precarga del isolate en paralelo al resto del flujo, para
      // que el modelo esté caliente cuando `_removeBackgroundSafe` lo espere.
      _segmentationWarmup = U2NetSegmentationService.prepare();
    }

    if (xFile == null) {
      // Un `null` de la galería es siempre un "atrás" del usuario: no hay
      // nada que avisar. Con la cámara, en cambio, puede significar que
      // Android reinició la Activity y la foto quedó en `retrieveLostData`:
      // se intenta recuperarla y, solo si tampoco hay nada, se avisa.
      if (fromCamera) {
        final handled = await _recoverLostImageIfAny();
        if (!mounted) return;
        if (!handled && _pickedImagePath == null && !_processingImage) {
          _abortImageLoad(notify: true);
        }
      }
      return;
    }

    // La foto debe existir en disco antes de tocar ningún estado de carga:
    // una ruta temporal inválida (proceso reiniciado, permiso revocado a
    // media captura...) dejaría la UI analizando algo que no está. Todo eso
    // lo comprueba [_beginAnalysis], que también fija la vista previa y lanza
    // el análisis.
    await _beginAnalysis(xFile);
  }

  /// Captura con la cámara embebida ([CameraCaptureScreen]) en vez del intent
  /// del sistema: la foto se toma sin salir del proceso de Flutter y llega ya
  /// guardada en una ruta permanente bajo el directorio de documentos, así que
  /// no puede perderse ni volver de 0 bytes (ver `CameraCaptureScreen`).
  Future<void> _captureWithInAppCamera() async {
    // Aun sin cambiar de proceso, la vista previa de la cámara reserva bastante
    // memoria: se libera el modelo U2-Netp mientras dura y se reprecarga al
    // volver, igual que en la ruta del intent nativo.
    unawaited(U2NetSegmentationService.dispose());
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const CameraCaptureScreen(),
        fullscreenDialog: true,
      ),
    );
    _segmentationWarmup = U2NetSegmentationService.prepare();
    if (!mounted || path == null) return;
    // `CameraCaptureScreen` ya deja la foto en disco (ruta permanente,
    // > 0 bytes); `_beginAnalysis` la revalida igualmente por consistencia.
    await _beginAnalysis(XFile(path));
  }

  /// Mejora la calidad de la foto y recorta el fondo de la prenda, ambos
  /// pasos EN PARALELO (`Future.wait`) a partir de los mismos bytes
  /// originales, ya que son independientes entre sí; solo el paso final
  /// (trasladar el canal alfa del recorte a la versión mejorada, SIN mezclar
  /// ningún color de fondo) depende de los dos. Todo 100% on-device: el
  /// recorte lo hace U2-Netp sobre ONNX Runtime y, si falla, se usa la foto
  /// mejorada sin recortar (ver _removeBackgroundSafe); sin red, sin coste.
  ///
  /// El PNG resultante se guarda con transparencia real: ningún color de
  /// fondo se compone en los píxeles.
  Future<void> _processImage(XFile original, {required String fallbackPath}) async {
    if (!mounted) return;

    // Última barrera antes de entrar en estado de carga: si el archivo no
    // existe o llegó vacío/truncado (ruta temporal ya limpiada, proceso muerto
    // a mitad de escribir la captura...) se corta aquí con un aviso específico
    // en vez de arrancar un análisis que solo puede fallar al decodificar y
    // dejaría la tarjeta en gris indefinidamente.
    if (!await _capturedFileIsUsable(original)) {
      debugPrint(
        '[AddGarmentScreen] La foto a procesar no existe o está vacía: '
        '${original.path}',
      );
      if (mounted) setState(() => _pickedImagePath = null);
      _abortImageLoad(notify: true, message: _incompletePhotoMessage);
      return;
    }

    setState(() => _processingImage = true);
    _progress.start();

    // Fase actual, para que el `catch` diga EN QUÉ paso falló (validación,
    // lectura, IA, composición o guardado) en vez de un genérico.
    var stage = 'lectura del archivo';
    try {
      final bytes = await original.readAsBytes();
      if (bytes.isEmpty) {
        // El archivo existía y tenía tamaño al comprobarlo, pero la lectura
        // volvió vacía (truncado entre la comprobación y la lectura): no hay
        // nada que analizar ni que previsualizar, así que se descarta la foto
        // y se pide repetir la captura, igual que en la barrera de entrada.
        debugPrint('[AddGarmentScreen] La foto se leyó como 0 bytes: ${original.path}');
        if (mounted) setState(() => _pickedImagePath = null);
        _abortImageLoad(notify: true, message: _incompletePhotoMessage);
        return;
      }
      debugPrint(
        '[AddGarmentScreen] Foto leída (${bytes.length} bytes); analizando…',
      );

      stage = 'mejora y recorte con IA local';
      // Los `.then()` son observadores puros: no cambian qué se espera ni
      // añaden latencia, solo le dicen a `_progress` cuándo termina CADA
      // future por separado para que el texto de fase refleje qué sigue
      // pendiente de verdad, en vez de un cronómetro a ciegas.
      final enhanceFuture = compute(enhanceGarmentPhoto, bytes)
        ..then((_) => _progress.onEnhanceDone());
      final cutoutFuture = _removeBackgroundSafe(bytes)
        ..then((_) => _progress.onCutoutDone());
      final results = await Future.wait([enhanceFuture, cutoutFuture]);
      final enhancedBytes = results[0]!;
      final cutoutBytes = results[1];
      _progress.onParallelDone(hasCutout: cutoutBytes != null);

      stage = 'composición de la imagen final';
      // El archivo PERSISTIDO siempre es un PNG con transparencia real: nunca
      // se mezcla ningún color de fondo en sus píxeles, así que se ve bien
      // sobre cualquier fondo, no solo sobre el neutro del tema actual.
      const extension = 'png';
      final Uint8List finalBytes = cutoutBytes == null
          // Sin snackbar a propósito: cuando la segmentación no encuentra un
          // sujeto claro (close-ups, fondos sin bordes definidos, modelo que
          // aún no ha terminado de cargar...) no debe sentirse como un error.
          // `renderSoftFallback` reescala/centra la
          // foto con esquinas redondeadas y transparencia real fuera de ese
          // rectángulo, como una tarjeta de producto, en vez de dejar la foto
          // sin procesar a pantalla completa.
          ? await compute(renderSoftFallback, SoftFallbackParams(enhancedBytes: enhancedBytes))
          : await compute(
              applyCutoutAlpha,
              CutoutAlphaParams(enhancedBytes: enhancedBytes, cutoutBytes: cutoutBytes),
            );

      stage = 'guardado en disco';
      final processedPath = await ImageStorage.persist(
        finalBytes,
        id: 'processed_${DateTime.now().microsecondsSinceEpoch}',
        extension: extension,
      );

      if (!mounted) return;
      setState(() => _pickedImagePath = processedPath);

      // Solo ahora, con el recorte local ya listo y visible, se dispara en
      // segundo plano el relleno automático del color.
      unawaited(_extractColor(cutoutBytes ?? enhancedBytes, hasAlpha: cutoutBytes != null));
    } catch (e, stackTrace) {
      debugPrint(
        '[AddGarmentScreen] Falló el procesado de la foto en la fase '
        '"$stage": $e\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        // La foto sigue cargada (la original sin procesar) y el formulario
        // pasa a edición manual: el análisis automático es opcional, así que
        // el usuario puede elegir el color a mano y guardar la prenda igual.
        _pickedImagePath = fallbackPath;
        _autoAnalysisFailed = true;
      });
      AppSnackBar.show(
        context,
        'No se pudo analizar la foto automáticamente. Elige el color a mano '
        'y guarda la prenda igualmente.',
        type: AppSnackBarType.warning,
        duration: const Duration(seconds: 5),
      );
    } finally {
      // Pase lo que pase (éxito, excepción, archivo ilegible, `return` desde
      // el catch por widget desmontado) la UI SIEMPRE sale del estado de
      // carga: nunca se queda "analizando" sin salida.
      _progress.stop();
      _processingImage = false;
      _recoveringLostImage = false;
      if (mounted) setState(() {});
    }
  }

  /// Calcula en local el color dominante de la prenda y lo deja listo en la
  /// tarjeta de datos automáticos. Sin red y determinista: la misma foto da
  /// siempre el mismo color.
  ///
  /// [hasAlpha] es `false` cuando no hubo recorte y solo tenemos la foto
  /// mejorada; el servicio lo compensa muestreando la zona central en vez de
  /// filtrar por transparencia.
  ///
  /// Un fallo aquí no molesta al usuario con un aviso: el color se queda sin
  /// rellenar y el selector manual sigue disponible, igual que antes.
  Future<void> _extractColor(Uint8List bytes, {required bool hasAlpha}) async {
    try {
      final result = await compute(
        extractGarmentColor,
        ColorExtractionParams(bytes: bytes, hasAlpha: hasAlpha),
      );
      if (!mounted) return;
      setState(() {
        _color = result.name;
        _colorSwatch = result.rgb;
      });
    } catch (e, stackTrace) {
      debugPrint('[AddGarmentScreen] No se pudo calcular el color: $e\n$stackTrace');
      // El recorte pudo salir bien pero el color no: se ofrece el chip de
      // selección manual en vez de dejar el shimmer girando para siempre.
      if (mounted) setState(() => _autoAnalysisFailed = true);
    }
  }

  /// Recorta la prenda con U2-Netp sobre ONNX Runtime
  /// (`U2NetSegmentationService`), 100% en el dispositivo y sin descargar nada.
  ///
  /// Ningún fallo se propaga: si el modelo no está disponible o no encuentra la
  /// prenda, devolver `null` evita tumbar el `Future.wait` junto con la mejora
  /// de imagen y hace que el llamador use el respaldo de "mejorada sin
  /// recortar".
  Future<Uint8List?> _removeBackgroundSafe(Uint8List bytes) async {
    try {
      // Tras una recreación del proceso el isolate de ONNX Runtime arranca de
      // cero. Esperar aquí a la precarga lanzada en `initState` garantiza que
      // el modelo termina de cargar ANTES de pedirle la inferencia, en vez de
      // competir con ella por el primer arranque. `prepare()` nunca lanza (se
      // reintentará dentro de `removeBackground` si la precarga falló).
      await (_segmentationWarmup ??= U2NetSegmentationService.prepare());
      return await U2NetSegmentationService.removeBackground(bytes);
    } catch (e, stackTrace) {
      debugPrint(
        '[AddGarmentScreen] U2-Netp no pudo recortar la prenda, se usa la '
        'foto mejorada sin recortar: $e\n$stackTrace',
      );
      return null;
    }
  }

  /// Abre [CropEditScreen] sobre la foto ya procesada para retocar a mano el
  /// recorte automático, y sustituye la vista previa por el PNG resultante.
  /// Reutiliza [ImageStorage.readBytes]/[ImageStorage.persist] tal cual las
  /// usa `_processImage`/`_finalizeImage`: mismas rutas multiplataforma
  /// (archivo real en móvil, data URL en Web), sin lógica nueva de E/S.
  Future<void> _adjustCrop() async {
    final path = _pickedImagePath;
    if (path == null || _processingImage) return;

    final bytes = await ImageStorage.readBytes(path);
    if (!mounted) return;

    final edited = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropEditScreen(imageBytes: bytes)),
    );
    if (edited == null || !mounted) return;

    final newPath = await ImageStorage.persist(
      edited,
      id: 'processed_${DateTime.now().microsecondsSinceEpoch}',
      extension: 'png',
    );
    if (!mounted) return;
    setState(() => _pickedImagePath = newPath);
  }

  Future<void> _save() async {
    // Reentrada: el botón ya se deshabilita con `_saving`, pero un doble toque
    // muy rápido (antes del rebuild) podría colar una segunda llamada y hacer
    // un `Navigator.pop` de más sobre la pantalla anterior.
    if (_saving) return;
    HapticFeedback.mediumImpact();
    if (_pickedImagePath == null) {
      AppSnackBar.show(context, 'Selecciona una foto primero', type: AppSnackBarType.error);
      return;
    }
    // El botón ya está deshabilitado mientras falten, pero se comprueba
    // igualmente: es lo que garantiza que ninguna prenda se guarde con una
    // categoría, un estilo o una temporada inventados por un valor por
    // defecto.
    if (_missingUserFields) {
      AppSnackBar.show(
        context,
        'Elige ${_missingFieldsLabel()} antes de guardar',
        type: AppSnackBarType.error,
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final finalImagePath = await _finalizeImage(_pickedImagePath!, id);

      final garment = Garment(
        id: id,
        imagePath: finalImagePath,
        category: _tipoPrenda!.categoria,
        // El color puede seguir sin calcularse si la foto falló: se guarda el
        // primer valor de la paleta, corregible después, en vez de bloquear
        // el guardado por un dato que la app se compromete a deducir sola.
        color: _color ?? garmentColorOptions.first,
        style: _style!,
        season: _season!,
        accessoryType: _tipoPrenda!.accessoryType,
        tipoPrendaId: _tipoPrenda!.id,
        isFavorite: _isFavorite,
        createdAt: DateTime.now(),
      );

      if (!mounted) return;
      await context.read<WardrobeProvider>().addGarment(garment);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Nombra en lenguaje natural los campos que el usuario aún no ha elegido,
  /// para que tanto el aviso bajo el botón como el snackbar digan qué falta
  /// exactamente en vez de un genérico "faltan datos".
  String _missingFieldsLabel() {
    final missing = <String>[
      if (_tipoPrenda == null) 'tipo de prenda',
      if (_style == null) 'estilo',
      if (_season == null) 'temporada',
    ];
    return missing.join(' y ');
  }

  /// Las rutas Web ya son data URLs autocontenidas y no requieren copia. En
  /// móvil, la vista previa apunta a un archivo temporal de image_picker (o
  /// al resultado ya mejorado/recortado en /processed), así que se copia a
  /// un destino permanente con el id definitivo de la prenda.
  Future<String> _finalizeImage(String path, String id) async {
    if (kIsWeb) return path;
    final extension = path.split('.').last;
    final bytes = await XFile(path).readAsBytes();
    return ImageStorage.persist(bytes, id: id, extension: extension);
  }

  Future<T?> _showOptionPicker<T>({
    required String title,
    required List<T> options,
    required T? current,
    required String Function(T) labelOf,
  }) {
    return showGlassSheet<T>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    ChoiceChip(
                      label: Text(labelOf(option)),
                      selected: option == current,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop(option);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editColor() async {
    final picked = await _showOptionPicker<String>(
      title: 'Color',
      options: garmentColorOptions,
      current: _color,
      labelOf: (c) => c,
    );
    if (picked != null) {
      setState(() {
        _color = picked;
        // La muestra pintaba el color MEDIDO en la foto; si el usuario elige
        // otro nombre a mano, esa muestra ya no lo representa y se sustituye
        // por el color de referencia de la paleta.
        _colorSwatch = GarmentPalette.rgbFor(picked);
      });
    }
  }

  /// Abre el selector de 2 pasos (familia + grid) a pantalla casi completa,
  /// igual que el diseño de referencia "Seleccionar Prenda". A diferencia de
  /// [_showOptionPicker], necesita casi toda la altura de la pantalla para
  /// el grid, así que usa `DraggableScrollableSheet` en vez de un `Wrap`.
  Future<void> _editTipoPrenda() async {
    final result = await showGlassSheet<TipoPrenda>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Seleccionar prenda',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SelectorPrendaWidget(
                  seleccionInicial: _tipoPrenda,
                  onPrendaSeleccionada: (tipo) {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pop(tipo);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (result != null) setState(() => _tipoPrenda = result);
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _pickedImagePath != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('Añadir prenda')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          kPageMargin,
          glassBodyTopPadding(context) + 12,
          kPageMargin,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _ImagePickerCard(
            imagePath: _pickedImagePath,
            isProcessing: _processingImage,
            phaseText: _progress.phaseText,
            onTap: _processingImage ? null : _pickImage,
            onAdjustCrop: _processingImage ? null : _adjustCrop,
          ),
          const SizedBox(height: 16),
          _AutoDetectedCard(
            hasImage: hasImage,
            color: _color,
            colorSwatch: _colorSwatch,
            analysisFailed: _autoAnalysisFailed,
            isFavorite: _isFavorite,
            onEditColor: _editColor,
            onToggleFavorite: (value) => setState(() => _isFavorite = value),
          ),
          const SizedBox(height: 16),
          _UserFieldsCard(
            tipoPrenda: _tipoPrenda,
            style: _style,
            season: _season,
            onEditTipoPrenda: _editTipoPrenda,
            onStyleChanged: (value) => setState(() => _style = value),
            onSeasonChanged: (value) => setState(() => _season = value),
            seasonIconOf: _seasonIcon,
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: PressableScale.passive(child: ElevatedButton.icon(
              onPressed:
                  (_saving || _processingImage || _missingUserFields) ? null : _save,
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.check),
              label: const Text('Guardar prenda'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            )),
          ),
          // Un botón deshabilitado sin explicación se lee como un fallo de la
          // app; este aviso nombra exactamente lo que falta por elegir.
          if (hasImage && _missingUserFields) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 15,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Elige ${_missingFieldsLabel()} para poder guardar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const _StyleTipCard(),
        ],
      ),
    );
  }

  static IconData _seasonIcon(GarmentSeason season) {
    switch (season) {
      case GarmentSeason.primavera:
        return Icons.local_florist_outlined;
      case GarmentSeason.verano:
        return Icons.wb_sunny_outlined;
      case GarmentSeason.otono:
        return Icons.eco_outlined;
      case GarmentSeason.invierno:
        return Icons.ac_unit_outlined;
      case GarmentSeason.todoElAno:
        return Icons.all_inclusive_outlined;
    }
  }
}

/// Texto de fase que se ve durante `_processImage`, sincronizado con señales
/// REALES en vez de un cronómetro a ciegas: `enhanceGarmentPhoto` y el
/// recorte corren en paralelo (`Future.wait` en `_processImage`), así que el
/// único momento fijo es el arranque; todo lo demás lo deciden `onEnhanceDone`
/// / `onCutoutDone` / `onParallelDone`, llamados desde observadores `.then()`
/// que NO alteran qué se espera ni añaden latencia al pipeline real.
///
/// El único tiempo inventado es [_minPhaseDisplay]: un piso para que ningún
/// texto se vea menos de eso, aunque la fase real termine antes (evita
/// parpadeo). Nunca fuerza un avance que no esté respaldado por una señal
/// real, así que en un fallback lento (Nivel 2/3) el texto simplemente se
/// queda quieto en vez de fingir progreso.
class _GarmentProcessingProgress {
  static const _minPhaseDisplay = Duration(milliseconds: 900);

  final phaseText = ValueNotifier<String>(_analizando);

  static const _analizando = 'Analizando prenda…';
  static const _recortando = 'Recortando el fondo…';
  static const _ajustando = 'Ajustando color y nitidez…';
  static const _puliendo = 'Puliendo los bordes…';
  static const _preparando = 'Preparando vista previa…';

  bool _enhanceDone = false;
  bool _cutoutDone = false;
  bool _parallelDone = false;
  DateTime _phaseShownAt = DateTime.now();
  Timer? _timer;

  void start() {
    _timer?.cancel();
    _enhanceDone = false;
    _cutoutDone = false;
    _parallelDone = false;
    _setPhase(_analizando);
    _timer = Timer(_minPhaseDisplay, _showPendingWork);
  }

  /// `enhanceGarmentPhoto` terminó. No hace falta cambiar nada: si el
  /// recorte sigue pendiente, "Recortando el fondo…" ya es el texto por
  /// defecto en cuanto pase el piso inicial.
  void onEnhanceDone() => _enhanceDone = true;

  /// El recorte (U2-Netp y sus fallbacks) terminó. Si el ajuste de color
  /// sigue vivo, es el único paso que queda del bloque paralelo: se refleja
  /// en el texto.
  void onCutoutDone() {
    _cutoutDone = true;
    if (!_parallelDone && !_enhanceDone) {
      _scheduleTransition(_ajustando);
    }
  }

  /// `Future.wait` de `_processImage` ya resolvió: los dos pasos paralelos
  /// terminaron de verdad. `hasCutout` decide si lo que sigue es pulir
  /// bordes reales o el respaldo sin recorte (Nivel 3).
  void onParallelDone({required bool hasCutout}) {
    _parallelDone = true;
    _scheduleTransition(hasCutout ? _puliendo : _preparando);
  }

  void _showPendingWork() {
    if (_parallelDone) return;
    _setPhase(_cutoutDone ? _ajustando : _recortando);
  }

  /// Cambia de fase respetando el piso anti-parpadeo: si la fase actual
  /// lleva menos de [_minPhaseDisplay] visible, retrasa el cambio lo que
  /// falte; si ya cumplió el mínimo, cambia al momento. Nunca retrasa nada
  /// del `await` real en `_processImage`, solo el texto en pantalla.
  void _scheduleTransition(String text) {
    _timer?.cancel();
    final remaining = _minPhaseDisplay - DateTime.now().difference(_phaseShownAt);
    if (remaining <= Duration.zero) {
      _setPhase(text);
    } else {
      _timer = Timer(remaining, () => _setPhase(text));
    }
  }

  void _setPhase(String text) {
    _phaseShownAt = DateTime.now();
    phaseText.value = text;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    phaseText.dispose();
  }
}

/// Tarjeta del único dato que la app rellena SOLA: el color, medido en
/// local sobre los píxeles del recorte. Mientras se resuelve muestra
/// shimmer; una vez listo es un chip que se puede tocar para corregirlo.
///
/// Va deliberadamente separada de [_UserFieldsCard] para que se vea de un
/// vistazo qué ha puesto la app y qué tiene que poner el usuario.
class _AutoDetectedCard extends StatelessWidget {
  final bool hasImage;
  final String? color;

  /// Color exacto medido en la foto, para pintar la muestra junto al nombre.
  final int? colorSwatch;

  /// `true` si el análisis automático falló para esta foto: en vez del
  /// shimmer (que sugiere "aún calculando") se muestra un chip de selección
  /// manual del color, para que el formulario quede claramente en modo
  /// edición manual y el usuario pueda guardar sin el análisis.
  final bool analysisFailed;

  final bool isFavorite;
  final VoidCallback onEditColor;
  final ValueChanged<bool> onToggleFavorite;

  const _AutoDetectedCard({
    required this.hasImage,
    required this.color,
    required this.colorSwatch,
    required this.analysisFailed,
    required this.isFavorite,
    required this.onEditColor,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: palette.cardBeige,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cardHairlineColor(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: scheme.secondary),
              const SizedBox(width: 8),
              Text(
                'Detectado automáticamente',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  fontSize: 15,
                  color: palette.strongText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasImage)
            Text(
              'Añade una foto y la app detectará solo el color.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.textSecondary,
                  ),
            )
          else ...[
            if (analysisFailed && color == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'No se pudo detectar el color. Elígelo a mano; el resto de '
                  'campos ya se completan manualmente.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (color != null)
                        _EditableAiChip(
                          label: color!,
                          onTap: onEditColor,
                          swatch: colorSwatch,
                        )
                      else if (analysisFailed)
                        _EditableAiChip(
                          label: 'Elegir color',
                          onTap: onEditColor,
                        )
                      else
                        const _ChipShimmer(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _FavoriteChip(isFavorite: isFavorite, onChanged: onToggleFavorite),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Hueco con shimmer del tamaño de un chip, mientras su valor se calcula.
class _ChipShimmer extends StatelessWidget {
  const _ChipShimmer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 96,
      child: ShimmerBox(
        height: 32,
        borderRadius: BorderRadius.all(Radius.circular(30)),
      ),
    );
  }
}

/// Tarjeta de los datos que SOLO puede aportar el usuario: categoría, estilo
/// y temporada (más el tipo de complemento, solo cuando la categoría elegida
/// es "Complemento"). La categoría ya no la detecta la IA (ver
/// [_AutoDetectedCard]): igual que el estilo y la temporada, no depende de
/// la foto sino de lo que el usuario decide sobre la prenda, así que la app
/// no la adivina.
///
/// Arranca sin ninguna opción marcada a propósito: un valor preseleccionado se
/// leería como una sugerencia ya hecha y el usuario lo aceptaría sin mirar. La
/// cabecera avisa en el color de aviso del tema mientras falte algo y pasa a
/// verde con un check cuando todos los campos requeridos están elegidos.
class _UserFieldsCard extends StatelessWidget {
  final TipoPrenda? tipoPrenda;
  final GarmentStyle? style;
  final GarmentSeason? season;
  final VoidCallback onEditTipoPrenda;
  final ValueChanged<GarmentStyle> onStyleChanged;
  final ValueChanged<GarmentSeason> onSeasonChanged;
  final IconData Function(GarmentSeason) seasonIconOf;

  const _UserFieldsCard({
    required this.tipoPrenda,
    required this.style,
    required this.season,
    required this.onEditTipoPrenda,
    required this.onStyleChanged,
    required this.onSeasonChanged,
    required this.seasonIconOf,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final complete = tipoPrenda != null && style != null && season != null;
    // Mismo par icono/color que usa AppSnackBarType.warning, para que "falta
    // algo" se vea igual en toda la app.
    final accent = complete ? const Color(0xFF3F7A52) : scheme.secondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: palette.cardBeige,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: complete ? cardHairlineColor(context) : accent.withValues(alpha: 0.55),
            width: complete ? 1 : 1.4,),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                complete ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  complete ? 'Completado por ti' : 'Complétalo tú',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    fontSize: 15,
                    color: palette.strongText,
                  ),
                ),
              ),
              if (!complete)
                Text(
                  'OBLIGATORIO',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Esto no lo detecta la IA: la categoría, el estilo y la temporada '
            'los eliges tú.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: palette.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          _FieldLabel(label: 'Tipo de prenda', chosen: tipoPrenda != null, accent: accent),
          const SizedBox(height: 8),
          _TipoPrendaField(tipoPrenda: tipoPrenda, onTap: onEditTipoPrenda),
          const SizedBox(height: 18),
          _FieldLabel(label: 'Estilo', chosen: style != null, accent: accent),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in GarmentStyle.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: style == option,
                  // Sin checkmark: al seleccionarlo el chip no cambia de
                  // ancho, así que el `Wrap` no se recoloca y los chips
                  // mantienen su posición en la cuadrícula.
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onStyleChanged(option);
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          _FieldLabel(label: 'Temporada', chosen: season != null, accent: accent),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in GarmentSeason.values)
                ChoiceChip(
                  avatar: Icon(seasonIconOf(option), size: 16),
                  label: Text(option.label),
                  selected: season == option,
                  // Sin checkmark: así el icono de temporada se mantiene al
                  // seleccionar y el chip no cambia de ancho, evitando que el
                  // `Wrap` recoloque el resto de chips.
                  showCheckmark: false,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    onSeasonChanged(option);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Título de un campo manual con su estado: mientras no se ha elegido nada
/// muestra "Selecciona una opción" en el color de aviso, para que un grupo de
/// chips sin marcar no se confunda con un valor ya puesto.
class _FieldLabel extends StatelessWidget {
  final String label;
  final bool chosen;
  final Color accent;

  const _FieldLabel({
    required this.label,
    required this.chosen,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.3,
            color: palette.strongText,
          ),
        ),
        const SizedBox(width: 8),
        if (!chosen)
          Text(
            'Selecciona una opción',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
      ],
    );
  }
}

/// Campo pulsable que abre el selector de 2 pasos ([SelectorPrendaWidget])
/// y muestra el tipo de prenda ya elegido (icono + nombre), o una invitación
/// a elegir cuando aún no hay ninguno.
class _TipoPrendaField extends StatelessWidget {
  final TipoPrenda? tipoPrenda;
  final VoidCallback onTap;

  const _TipoPrendaField({required this.tipoPrenda, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final tipo = tipoPrenda;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: palette.chipBeige,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: palette.chipBeigeBorder),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                tipo?.icono ?? Icons.checkroom_outlined,
                size: 20,
                color: tipo != null ? palette.strongText : palette.iconMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tipo?.nombre ?? 'Toca para elegir',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    letterSpacing: 0.2,
                    color: tipo != null ? palette.strongText : palette.textSecondary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: palette.iconMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableAiChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// Muestra circular del color (0xRRGGBB) que acompaña al nombre. Solo la
  /// usa el chip de color: enseñar el tono exacto medido en la foto deja
  /// claro que el dato sale de la prenda y no de una etiqueta escogida a ojo.
  final int? swatch;

  const _EditableAiChip({required this.label, required this.onTap, this.swatch});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return PressableScale(
      onTap: onTap,
      haptic: PressHaptic.selection,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: palette.chipBeige,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: palette.chipBeigeBorder),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (swatch != null) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(0xFF000000 | swatch!),
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.chipBeigeBorder),
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.4,
                  color: palette.strongText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteChip extends StatelessWidget {
  final bool isFavorite;
  final ValueChanged<bool> onChanged;

  const _FavoriteChip({required this.isFavorite, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return PressableScale(
      onTap: () => onChanged(!isFavorite),
      haptic: PressHaptic.selection,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: ShapeDecoration(
          color: isFavorite ? palette.favoritePinkBg : palette.chipBeige,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(color: isFavorite ? palette.favoritePinkBg : palette.chipBeigeBorder),
          ),
        ),
        child: Text(
          'Favorita',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.4,
            color: isFavorite ? palette.favoritePinkText : palette.strongText,
          ),
        ),
      ),
    );
  }
}

/// Nota decorativa muy sutil al final del formulario: un consejo de estilo
/// y una marca de agua discreta con el nombre de la app, en tonos beige y
/// gris apagado para no competir con el resto de la pantalla.
class _StyleTipCard extends StatelessWidget {
  const _StyleTipCard();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: ShapeDecoration(
        color: palette.cardBeige.withValues(alpha: 0.6),
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Consejo de estilo: combina prendas neutras para crear un '
            'armario cápsula versátil.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'ARMARIO VIRTUAL',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: palette.strongText.withValues(alpha: 0.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  final String? imagePath;
  final bool isProcessing;

  /// Texto de fase actual (ver [_GarmentProcessingProgress]); solo se lee
  /// mientras [isProcessing] es true.
  final ValueListenable<String> phaseText;
  final VoidCallback? onTap;

  /// Abre [CropEditScreen] sobre la foto ya procesada. Null mientras no haya
  /// imagen o se esté procesando (mismo criterio que [onTap]), para que el
  /// botón de ajustar recorte no aparezca sobre un placeholder ni compita
  /// con el "Cambiar foto" mientras la foto todavía se está recortando.
  final VoidCallback? onAdjustCrop;

  const _ImagePickerCard({
    required this.imagePath,
    required this.isProcessing,
    required this.phaseText,
    required this.onTap,
    required this.onAdjustCrop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = Theme.of(context).extension<AppPalette>()!;
    final radius = BorderRadius.circular(16);
    final hasImage = imagePath != null;

    return PressableScale(
      onTap: onTap,
      enableHaptics: false,
      child: Container(
        height: 280,
        decoration: ShapeDecoration(
          color: scheme.surfaceContainerHighest,
          shape: RoundedSuperellipseBorder(
            borderRadius: radius,
            side: BorderSide(color: hasImage ? Colors.transparent : scheme.outline,
              width: 1.4,),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            hasImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // La prenda guardada tiene transparencia real (ver
                      // `applyCutoutAlpha`/`renderSoftFallback`): este color
                      // es puramente decorativo, pintado DETRÁS de la imagen,
                      // nunca compuesto en sus píxeles. Es lo que hace que la
                      // vista previa de edición se vea igual que se verá la
                      // prenda cuando de verdad tenga fondo transparente.
                      ColoredBox(color: palette.garmentPhotoBackground),
                      GarmentImage(imagePath: imagePath!, fit: BoxFit.cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.55),
                            ],
                            stops: const [0.6, 1],
                          ),
                        ),
                      ),
                      if (!isProcessing && onAdjustCrop != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(30),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(30),
                              onTap: onAdjustCrop,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.brush_outlined,
                                      size: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Ajustar recorte',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!isProcessing)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 14,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              decoration: ShapeDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              // Este pill flota sobre la foto de la prenda con un
                              // fondo casi blanco fijo (para seguir siendo legible
                              // encima de cualquier foto), independiente del tema:
                              // `scheme.primary` variaría a un verde salvia claro
                              // en modo oscuro, con contraste insuficiente sobre
                              // ese mismo blanco. Se usa un gris grafito fijo en
                              // su lugar, igual en los dos modos.
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.autorenew,
                                    size: 16,
                                    color: AppColors.textPrimary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Cambiar foto',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.secondary.withValues(alpha: 0.14),
                        ),
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: 32,
                          color: scheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Toca para añadir una foto',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cámara o galería',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
            // Mientras se procesa, la foto sin recortar deja de verse: en su
            // lugar se muestra el mismo lienzo neutro (`garmentPhotoBackground`)
            // sobre el que aparecerá la prenda ya recortada al terminar, con un
            // shimmer sutil para dejar claro que la app sigue trabajando. El
            // texto de fase viene de [phaseText] (ver [_GarmentProcessingProgress]
            // en `_AddGarmentScreenState`); el subtítulo de abajo es fijo y no
            // depende de ninguna fase, para gestionar la expectativa desde el
            // primer frame.
            if (isProcessing) ...[
              ShimmerBox(
                borderRadius: BorderRadius.zero,
                baseColor: palette.garmentPhotoBackground,
                highlightColor: palette.chipBeigeBorder,
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<String>(
                      valueListenable: phaseText,
                      builder: (context, text, _) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          text,
                          key: ValueKey(text),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: palette.strongText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Esto puede tardar unos segundos',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
