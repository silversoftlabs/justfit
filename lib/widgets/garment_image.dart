import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Renderiza la imagen de una prenda de forma multiplataforma.
///
/// `imagePath` puede ser: una ruta de archivo real (móvil/desktop), una
/// data URL `data:<mime>;base64,<...>` (usada en Web, donde no hay sistema
/// de archivos persistente) o una URL http(s) normal.
class GarmentImage extends StatelessWidget {
  final String imagePath;
  final BoxFit fit;

  /// Cuando no es null, envuelve la imagen en un [Hero] con esta etiqueta.
  /// Solo debe usarse en pantallas donde la prenda aparece una única vez en
  /// la ruta (la tarjeta de la rejilla y su pantalla de detalle); nunca en
  /// la pantalla de outfits, donde una misma prenda puede repetirse en
  /// varias tarjetas a la vez y provocar una colisión de etiquetas Hero.
  final String? heroTag;

  const GarmentImage({
    super.key,
    required this.imagePath,
    this.fit = BoxFit.cover,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final image = _buildImage();
    final tag = heroTag;
    if (tag == null) return image;
    return Hero(tag: tag, child: image);
  }

  Widget _buildImage() {
    if (kIsWeb) {
      if (imagePath.startsWith('data:')) {
        return Image.memory(
          _decodeDataUrl(imagePath),
          fit: fit,
          frameBuilder: _frameBuilder,
          errorBuilder: _errorBuilder,
        );
      }
      return Image.network(
        imagePath,
        fit: fit,
        frameBuilder: _frameBuilder,
        errorBuilder: _errorBuilder,
      );
    }
    return Image.file(
      io.File(imagePath),
      fit: fit,
      frameBuilder: _frameBuilder,
      errorBuilder: _errorBuilder,
    );
  }

  static Widget _frameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: child,
    );
  }

  static Widget _errorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    return _ErrorPlaceholder();
  }

  static Uint8List _decodeDataUrl(String dataUrl) {
    final commaIndex = dataUrl.indexOf(',');
    return base64Decode(dataUrl.substring(commaIndex + 1));
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
