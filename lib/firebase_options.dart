// GENERADO AUTOMÁTICAMENTE — ESTE ES UN MARCADOR DE POSICIÓN.
//
// Ejecuta desde la raíz del proyecto:
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure --project=<TU_PROYECTO_FIREBASE>
//
// Ese comando SOBRESCRIBE este fichero con las claves reales del proyecto
// Firebase (una `FirebaseOptions` por plataforma) y crea
// `android/app/google-services.json`.
//
// Mientras tanto, `DefaultFirebaseOptions.currentPlatform` lanza una excepción
// que `main()` captura: la app arranca sin reporte de fallos.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase no está configurado todavía. Ejecuta `flutterfire configure` '
      'para generar lib/firebase_options.dart con las claves reales.',
    );
  }
}
