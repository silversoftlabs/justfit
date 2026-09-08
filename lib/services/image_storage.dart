import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Persiste bytes de imagen de forma multiplataforma y devuelve un
/// `imagePath` listo para guardar en un [Garment] y renderizar con
/// `GarmentImage`.
///
/// En Web no hay sistema de archivos persistente, así que los bytes se
/// codifican como data URL; en móvil/desktop se escriben a un archivo real
/// bajo el directorio de documentos de la app.
class ImageStorage {
  static Future<String> persist(
    Uint8List bytes, {
    required String id,
    required String extension,
  }) async {
    if (kIsWeb) {
      final mimeType = extension.toLowerCase() == 'png' ? 'image/png' : 'image/jpeg';
      return 'data:$mimeType;base64,${base64Encode(bytes)}';
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final garmentsDir = io.Directory('${docsDir.path}/garments');
    if (!await garmentsDir.exists()) {
      await garmentsDir.create(recursive: true);
    }

    final savedPath = '${garmentsDir.path}/$id.$extension';
    await io.File(savedPath).writeAsBytes(bytes);
    return savedPath;
  }

  /// Lee de vuelta los bytes de un `imagePath` ya persistido (contraparte de
  /// [persist]): decodifica la data URL en Web, lee el archivo real en el
  /// resto de plataformas.
  static Future<Uint8List> readBytes(String imagePath) async {
    if (kIsWeb) {
      final commaIndex = imagePath.indexOf(',');
      return base64Decode(imagePath.substring(commaIndex + 1));
    }
    return io.File(imagePath).readAsBytes();
  }
}
