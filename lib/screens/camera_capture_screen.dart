import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/image_storage.dart';
import '../widgets/pressable_scale.dart';

/// Captura de foto DENTRO del proceso de Flutter, sin lanzar la app de cámara
/// del sistema.
///
/// Motivo: en gama baja Android liquida el proceso de la app por falta de
/// memoria mientras la cámara nativa —un proceso aparte y pesado— está en
/// primer plano, y al volver entrega un archivo de 0 bytes al intent. Con la
/// cámara embebida todo ocurre en ESTE proceso, que nunca deja de estar en
/// primer plano, y la foto se escribe a
/// `getApplicationDocumentsDirectory()/garments/` (ruta permanente, vía
/// [ImageStorage.persist]) ANTES de devolverla, así que no puede perderse ni
/// llegar vacía.
///
/// `Navigator.pop` devuelve la ruta absoluta del JPG capturado, o `null` si el
/// usuario cierra sin hacer foto.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  /// Id fijo (no timestamped) para el archivo de captura: se sobrescribe en
  /// cada foto, así queda como mucho UN temporal en disco, nunca una pila.
  /// El pipeline de análisis lo recopia luego a su propio nombre definitivo.
  static const _captureFileId = 'camera_capture';

  CameraController? _controller;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tras el primer frame para no llamar a `setState` durante `initState`
    // (`_initCamera` lo hace nada más entrar). Los campos ya arrancan en
    // "inicializando", así que el spinner se ve desde el primer frame igual.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initCamera());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    // Patrón recomendado por el paquete `camera`: soltar la cámara al pasar a
    // segundo plano (otra app puede necesitarla) y volver a crearla al
    // recuperar el foco.
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  Future<void> _initCamera() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    // Suelta cualquier controlador previo (reintento o vuelta de segundo
    // plano) antes de crear el nuevo.
    await _controller?.dispose();
    _controller = null;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No se encontró ninguna cámara en el dispositivo.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        // 1080p: de sobra para el modelo de recorte (entra a 1024 px) y para
        // la vista de detalle, sin el buffer gigante de la resolución máxima
        // del sensor que dispararía la memoria.
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _initializing = false);
    } on CameraException catch (e) {
      _fail(_messageForException(e));
    } catch (e) {
      _fail('No se pudo iniciar la cámara: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _initializing = false;
    });
  }

  String _messageForException(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'La cámara no tiene permiso. Actívalo en los ajustes del '
            'sistema o usa la galería.';
      case 'cameraPermission':
        return 'La cámara no tiene permiso. Actívalo en los ajustes del '
            'sistema o usa la galería.';
      default:
        return 'No se pudo iniciar la cámara (${e.code}).';
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      final bytes = await shot.readAsBytes();
      if (bytes.isEmpty) {
        throw CameraException('emptyCapture', 'la cámara devolvió 0 bytes');
      }
      // Copia a ruta permanente ANTES de devolverla: la `XFile` del plugin
      // vive en un temporal de la caché que el sistema puede limpiar.
      final savedPath = await ImageStorage.persist(
        bytes,
        id: _captureFileId,
        extension: 'jpg',
      );
      // El temporal del plugin ya está copiado: se borra para no dejar
      // duplicados ocupando espacio.
      try {
        await File(shot.path).delete();
      } catch (_) {
        // Si el sistema ya lo limpió, no pasa nada.
      }
      if (!mounted) return;
      Navigator.of(context).pop(savedPath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo tomar la foto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBody(),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      return _CameraError(message: error, onRetry: _initCamera);
    }

    final controller = _controller;
    if (_initializing || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(controller)),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: _ShutterButton(
              busy: _capturing,
              onTap: _capture,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;

  const _ShutterButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: busy ? null : onTap,
      haptic: PressHaptic.medium,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.25),
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _CameraError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Volver'),
                ),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
