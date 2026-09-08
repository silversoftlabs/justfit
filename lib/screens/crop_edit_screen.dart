import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../theme/app_palette.dart';

/// Pantalla de edición manual del recorte de una prenda: deja retocar a mano
/// el canal alfa de la foto ya procesada (ver `applyCutoutAlpha` /
/// `renderSoftFallback` en `services/image_compositor.dart`) pintando con el
/// dedo, para arreglar lo que la segmentación automática dejó mal.
///
/// Solo recibe la imagen YA procesada ([imageBytes]), no una "original" por
/// separado: el compositor final siempre guarda el RGB de la foto mejorada en
/// TODOS los píxeles, incluidos los que quedaron transparentes por el recorte
/// automático (`applyCutoutAlpha` solo sustituye el canal alfa, nunca el
/// color). Por eso "Restaurar" no necesita traer la foto sin recortar consigo:
/// basta con devolver el alfa de un píxel a 255, su color ya está debajo.
///
/// Excepción conocida: en el respaldo sin segmentación real
/// (`renderSoftFallback`), el área fuera de la tarjeta reescalada nunca tuvo
/// color asignado (queda en negro transparente), así que "restaurar" ahí
/// pintaría negro opaco. No es una regresión práctica: ese camino no recorta
/// ninguna prenda real que haga falta restaurar, al no existir una máscara de
/// segmentación que corregir.
class CropEditScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const CropEditScreen({super.key, required this.imageBytes});

  @override
  State<CropEditScreen> createState() => _CropEditScreenState();
}

enum _BrushMode { restore, erase }

/// Cambios de un único trazo (gesto de pan completo), para poder deshacerlo
/// de una vez. Solo guarda el alfa ANTERIOR de cada píxel realmente tocado
/// (indexado por `y * width + x`), no una copia de la imagen entera: un
/// retoque típico cubre una fracción pequeña del lienzo, así que el coste de
/// memoria del historial de deshacer queda acotado por lo que el usuario ha
/// pintado de verdad, no por el tamaño de la foto.
class _StrokeChange {
  final Map<int, int> beforeAlpha = {};
}

/// Traduce entre coordenadas del lienzo (donde llegan los gestos) y
/// coordenadas de píxel de la imagen, según cómo `BoxFit.contain` la centra y
/// escala dentro del lienzo disponible.
class _FitTransform {
  final double scale;
  final Offset origin;

  const _FitTransform({required this.scale, required this.origin});

  Offset toImage(Offset canvasPoint) => (canvasPoint - origin) / scale;
}

class _CropEditScreenState extends State<CropEditScreen> {
  img.Image? _working;
  ui.Image? _display;
  bool _loading = true;

  /// true mientras se regenera la imagen de pantalla tras un trazo o un
  /// deshacer, o mientras se codifica el PNG final al aplicar: bloquea el
  /// inicio de un nuevo trazo para no solapar dos regeneraciones a la vez.
  bool _busy = false;

  _BrushMode _mode = _BrushMode.erase;
  double _brushDiameter = 36;

  final List<_StrokeChange> _undoStack = [];
  static const _maxUndoSteps = 20;

  final List<Offset> _activePoints = [];
  _StrokeChange? _activeChange;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final decoded = await compute(_decodeAsRgba, widget.imageBytes);
      final display = await _toUiImage(decoded);
      if (!mounted) return;
      setState(() {
        _working = decoded;
        _display = display;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static img.Image _decodeAsRgba(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('No se pudo decodificar la imagen de la prenda');
    }
    return image.numChannels == 4 ? image : image.convert(numChannels: 4);
  }

  static Future<ui.Image> _toUiImage(img.Image image) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      image.getBytes(order: img.ChannelOrder.rgba),
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Uint8List _encodeAsPng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  _FitTransform _fitFor(Size canvasSize) {
    final image = _working!;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, canvasSize);
    final destination = fitted.destination;
    final scale = imageSize.width == 0 ? 1.0 : destination.width / imageSize.width;
    final origin = Offset(
      (canvasSize.width - destination.width) / 2,
      (canvasSize.height - destination.height) / 2,
    );
    return _FitTransform(scale: scale, origin: origin);
  }

  void _onPanStart(DragStartDetails details) {
    if (_busy || _working == null) return;
    _activeChange = _StrokeChange();
    _activePoints
      ..clear()
      ..add(details.localPosition);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeChange == null) return;
    // Umbral mínimo de movimiento: sin él, cada micro-evento de arrastre
    // añadiría un punto casi idéntico al anterior, disparando `setState` (y
    // por tanto un repintado) muchas más veces de las necesarias.
    if ((details.localPosition - _activePoints.last).distance < 2) return;
    _activePoints.add(details.localPosition);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails details, _FitTransform fit) {
    final change = _activeChange;
    final points = List<Offset>.of(_activePoints);
    _activeChange = null;
    _activePoints.clear();
    if (change == null || points.isEmpty) {
      setState(() {});
      return;
    }
    unawaited(_commitStroke(change, points, fit));
  }

  /// Aplica el trazo ya terminado a los píxeles reales de [_working] (el
  /// avance en vivo durante el gesto solo dibuja una previsualización en el
  /// `CustomPainter`, ver [_onPanUpdate]) y regenera la imagen de pantalla.
  ///
  /// El recorrido de píxeles corre en el isolate principal, no en
  /// `compute()`: a diferencia de decodificar o codificar la imagen entera,
  /// aquí solo se tocan los píxeles bajo el trazo (acotados por el diámetro
  /// del pincel), así que el coste es proporcional a lo pintado, no al
  /// tamaño de la foto, y no compensa el coste de copiar la imagen completa
  /// a otro isolate y de vuelta.
  Future<void> _commitStroke(
    _StrokeChange change,
    List<Offset> canvasPoints,
    _FitTransform fit,
  ) async {
    setState(() => _busy = true);
    final working = _working!;
    final radius = (_brushDiameter / 2) / fit.scale;
    final erase = _mode == _BrushMode.erase;

    Offset? previous;
    for (final point in canvasPoints) {
      final imagePoint = fit.toImage(point);
      if (previous == null) {
        _stampCircle(working, imagePoint, radius, erase, change);
      } else {
        _stampSegment(working, previous, imagePoint, radius, erase, change);
      }
      previous = imagePoint;
    }

    if (change.beforeAlpha.isNotEmpty) {
      _undoStack.add(change);
      if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    }

    final display = await _toUiImage(working);
    if (!mounted) return;
    setState(() {
      _display = display;
      _busy = false;
    });
  }

  /// Interpola círculos entre [from] y [to] (coordenadas de imagen) para que
  /// un arrastre rápido pinte un trazo continuo en vez de círculos sueltos
  /// con huecos entre ellos.
  void _stampSegment(
    img.Image image,
    Offset from,
    Offset to,
    double radius,
    bool erase,
    _StrokeChange change,
  ) {
    final distance = (to - from).distance;
    if (distance <= 0) {
      _stampCircle(image, to, radius, erase, change);
      return;
    }
    final stepSize = (radius / 2).clamp(1.0, 50.0);
    final steps = (distance / stepSize).ceil();
    for (var i = 1; i <= steps; i++) {
      _stampCircle(image, Offset.lerp(from, to, i / steps)!, radius, erase, change);
    }
  }

  /// Pone a 0 (borrar) o 255 (restaurar) el alfa de los píxeles de [image]
  /// dentro del círculo de centro [center] y radio [radius] (coordenadas de
  /// imagen), guardando en [change] el alfa previo de cada píxel tocado por
  /// primera vez en este trazo.
  void _stampCircle(
    img.Image image,
    Offset center,
    double radius,
    bool erase,
    _StrokeChange change,
  ) {
    final r = radius.clamp(1, 1000).round();
    final cx = center.dx.round();
    final cy = center.dy.round();
    final minX = (cx - r).clamp(0, image.width - 1);
    final maxX = (cx + r).clamp(0, image.width - 1);
    final minY = (cy - r).clamp(0, image.height - 1);
    final maxY = (cy + r).clamp(0, image.height - 1);
    if (minX > maxX || minY > maxY) return;
    final r2 = r * r;
    final pixel = image.getPixel(0, 0);
    final newAlpha = erase ? 0 : 255;

    for (var y = minY; y <= maxY; y++) {
      final dy = y - cy;
      for (var x = minX; x <= maxX; x++) {
        final dx = x - cx;
        if (dx * dx + dy * dy > r2) continue;
        image.getPixel(x, y, pixel);
        final index = y * image.width + x;
        change.beforeAlpha.putIfAbsent(index, () => pixel.a.toInt());
        image.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, newAlpha);
      }
    }
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty || _busy || _working == null) return;
    final change = _undoStack.removeLast();
    final working = _working!;
    setState(() => _busy = true);

    final pixel = working.getPixel(0, 0);
    for (final entry in change.beforeAlpha.entries) {
      final x = entry.key % working.width;
      final y = entry.key ~/ working.width;
      working.getPixel(x, y, pixel);
      working.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, entry.value);
    }

    final display = await _toUiImage(working);
    if (!mounted) return;
    setState(() {
      _display = display;
      _busy = false;
    });
  }

  Future<void> _apply() async {
    final working = _working;
    if (working == null || _busy) return;
    setState(() => _busy = true);
    final bytes = await compute(_encodeAsPng, working);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<AppPalette>()!;
    final ready = _working != null && _display != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustar recorte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Deshacer',
            onPressed: (_undoStack.isEmpty || _busy) ? null : _undo,
          ),
        ],
      ),
      body: SafeArea(
        child: !ready
            ? Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : Text(
                        'No se pudo cargar la imagen para editarla',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
              )
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                          final fit = _fitFor(canvasSize);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: GestureDetector(
                              key: const Key('cropEditCanvas'),
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: (details) => _onPanEnd(details, fit),
                              child: CustomPaint(
                                size: canvasSize,
                                painter: _CropPainter(
                                  image: _display!,
                                  fit: fit,
                                  previewPoints: _activePoints,
                                  previewRadius: _brushDiameter / 2,
                                  erasing: _mode == _BrushMode.erase,
                                  backgroundColor: palette.garmentPhotoBackground,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _CropControls(
                    mode: _mode,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                    brushDiameter: _brushDiameter,
                    onBrushDiameterChanged: (value) => setState(() => _brushDiameter = value),
                    onApply: _busy ? null : _apply,
                    busy: _busy,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Pinta la imagen de trabajo dentro del lienzo disponible (`BoxFit.contain`,
/// vía [_FitTransform]) sobre un fondo neutro que deja ver la transparencia
/// real de la prenda, más una previsualización en vivo del trazo activo (el
/// trazo NO toca los píxeles de verdad hasta soltar el dedo, ver
/// `_CropEditScreenState._commitStroke`).
class _CropPainter extends CustomPainter {
  final ui.Image image;
  final _FitTransform fit;
  final List<Offset> previewPoints;
  final double previewRadius;
  final bool erasing;
  final Color backgroundColor;

  _CropPainter({
    required this.image,
    required this.fit,
    required this.previewPoints,
    required this.previewRadius,
    required this.erasing,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final destinationSize = imageSize * fit.scale;
    final destinationRect = fit.origin & destinationSize;
    canvas.drawImageRect(
      image,
      Offset.zero & imageSize,
      destinationRect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    if (previewPoints.isEmpty) return;

    final paint = Paint()
      ..color = (erasing ? Colors.redAccent : Colors.lightBlueAccent).withValues(alpha: 0.5)
      ..strokeWidth = previewRadius * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (previewPoints.length == 1) {
      canvas.drawCircle(previewPoints.first, previewRadius, paint..style = PaintingStyle.fill);
      return;
    }

    paint.style = PaintingStyle.stroke;
    final path = Path()..moveTo(previewPoints.first.dx, previewPoints.first.dy);
    for (final point in previewPoints.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  // El trazo activo cambia en cada rebuild disparado por un evento de pan (la
  // misma lista de puntos se muta in-place), así que comparar identidad de
  // campos no distinguiría "cambió" de "no cambió": se repinta siempre. El
  // coste es bajo (una imagen y un trazo corto), acotado por el umbral de
  // distancia mínima entre puntos en `_onPanUpdate`.
  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) => true;
}

/// Controles inferiores: modo de pincel (restaurar/borrar), tamaño del
/// pincel y el botón para aplicar los cambios y devolver el PNG editado.
class _CropControls extends StatelessWidget {
  final _BrushMode mode;
  final ValueChanged<_BrushMode> onModeChanged;
  final double brushDiameter;
  final ValueChanged<double> onBrushDiameterChanged;
  final VoidCallback? onApply;
  final bool busy;

  const _CropControls({
    required this.mode,
    required this.onModeChanged,
    required this.brushDiameter,
    required this.onBrushDiameterChanged,
    required this.onApply,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_BrushMode>(
              segments: const [
                ButtonSegment(
                  value: _BrushMode.restore,
                  label: Text('Restaurar'),
                  icon: Icon(Icons.brush_outlined),
                ),
                ButtonSegment(
                  value: _BrushMode.erase,
                  label: Text('Borrar'),
                  icon: Icon(Icons.auto_fix_normal_outlined),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onModeChanged(selection.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.circle, size: 10),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 100,
                    value: brushDiameter,
                    label: brushDiameter.round().toString(),
                    onChanged: onBrushDiameterChanged,
                  ),
                ),
                const Icon(Icons.circle, size: 22),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onApply,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Aplicar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
