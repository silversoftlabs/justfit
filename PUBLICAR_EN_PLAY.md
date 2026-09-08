# Publicar Justfit en Google Play + Crashlytics

Empresa: **gamusinlab** · App: **Justfit** · `applicationId`: `com.gamusinlab.justfit`

Este documento resume lo que ya está configurado en el repo y los pasos que
**tú** tienes que dar (cuentas de Google, Firebase y Play Console).

---

## 1. Lo que ya está hecho (no toques nada de esto)

| Área | Cambio |
|---|---|
| **ID de app** | `com.armariovirtual.armario_virtual` → `com.gamusinlab.justfit` (namespace, `applicationId`, `MainActivity.kt` movido a `com/gamusinlab/justfit/`). |
| **Nombre visible** | `android:label` → `Justfit`. |
| **Firma de release** | Keystore generado en `android/app/justfit-upload-keystore.jks`. `android/app/build.gradle.kts` lee las credenciales de `android/key.properties` y firma el release con esa clave (antes usaba la de debug, que Play rechaza). Si `key.properties` no existe, cae a debug para no romper `flutter run --release`. |
| **Símbolos nativos** | `ndk { debugSymbolLevel = "SYMBOL_TABLE" }` → el AAB incluye las tablas de símbolos de `libonnxruntime.so`, `libflutter.so`, etc. para desofuscar crashes nativos en Play/Crashlytics. |
| **Crashlytics (código)** | `firebase_core` + `firebase_crashlytics` en `pubspec.yaml`. `lib/main.dart` inicializa Firebase y engancha Crashlytics a `FlutterError.onError`, `PlatformDispatcher.onError` y desactiva el envío en modo debug. |
| **Crashlytics (gradle)** | Plugins `com.google.gms.google-services` (4.5.0) y `com.google.firebase.crashlytics` (3.0.8) declarados en `android/settings.gradle.kts`. Se **aplican solos** en `android/app/build.gradle.kts` en cuanto exista `android/app/google-services.json`. |
| **.gitignore** | `android/.gitignore` excluye `key.properties`, `*.jks`, `*.keystore`. |
| **firebase_options.dart** | Marcador de posición en `lib/firebase_options.dart` que lanza excepción (capturada) hasta que lo sobrescriba `flutterfire configure`. |

Compilación verificada: `flutter build appbundle --release --dart-define-from-file=dart_define.json` → **OK** (104,8 MB),
`flutter test` → **176 OK**, `flutter analyze` → **sin problemas**.

---

## 2. ⚠️ Keystore — GUARDA ESTO YA

Si pierdes este keystore o su contraseña **no podrás volver a actualizar la app
en Play nunca más** (salvo un reset manual de Google que tarda días).

```
Fichero:      android/app/justfit-upload-keystore.jks   (formato PKCS12)
Alias:        upload
Contraseña:   DRvEUT1C66WUmhqDQQUC8Up7ILcA      (store y key: la misma)
Validez:      hasta 2054-01-22
SHA-1:        68:C4:6E:FD:7E:BC:86:B7:F3:85:35:A2:A6:A0:74:9D:DD:85:74:D9
SHA-256:      EE:D0:1A:F2:7B:64:34:78:06:3E:27:E5:3E:9D:C7:FA:3D:A1:25:4E:2A:08:9F:F2:F6:1D:F4:2A:B7:F6:76:E0
```

**Acción:** copia el `.jks` y esta contraseña a un gestor de contraseñas y a un
backup offline (disco externo / caja fuerte). No van en git.

> Con **Play App Signing** (recomendado, activado por defecto) esta clave es solo
> la *clave de subida*. Google guarda la clave real de firma. Si algún día
> pierdes esta, se puede resetear. Aun así: haz backup.

Las credenciales están en `android/key.properties` (ya creado, ignorado por git).

---

## 3. Configurar Firebase / Crashlytics

**Estado actual (ya comprobado):**
- `firebase-tools` 15.29.0 instalado y con sesión iniciada como **silversoftlabs@gmail.com** (cuenta elegida para el proyecto).
- `flutterfire_cli` 1.4.1 instalado. Su carpeta `%LOCALAPPDATA%\Pub\Cache\bin` se ha
  añadido al PATH de usuario → **abre una PowerShell nueva** para que `flutterfire`
  se reconozca (la sesión actual no lo verá).
- **Bloqueo pendiente:** la cuenta silversoftlabs no ha aceptado los Términos de
  Servicio de Google Cloud, así que no se puede crear el proyecto por CLI
  (`Error: Callers must accept Terms of Service`).

### 3.1 Crear el proyecto Firebase (en el navegador, una sola vez)

1. Entra en <https://console.firebase.google.com> con **silversoftlabs@gmail.com**.
2. *Crear un proyecto* → nombre **Justfit** → acepta los Términos de Servicio
   cuando lo pida. Google Analytics: opcional (no hace falta para Crashlytics).

### 3.2 Vincular la app Flutter (PowerShell nueva, en la raíz del repo)

```powershell
flutterfire configure --project=justfit --platforms=android --android-package-name=com.gamusinlab.justfit
```

(Sustituye `justfit` por el ID real del proyecto si la consola le puso otro,
p. ej. `justfit-1a2b3`.) Esto genera:

- `lib/firebase_options.dart` (sobrescribe el marcador de posición)
- `android/app/google-services.json` (a partir de aquí los plugins de Firebase
  se activan solos en la build)

Verifica:

```powershell
flutter build appbundle --release --dart-define-from-file=dart_define.json
```

### Probar que Crashlytics recibe eventos

Añade temporalmente un botón que llame a:

```dart
FirebaseCrashlytics.instance.crash();          // crash nativo forzado
// o, sin matar la app:
FirebaseCrashlytics.instance.recordError(Exception('prueba crashlytics'), StackTrace.current);
```

Compila en **release** (`flutter run --release`), pulsa el botón, reabre la app
(los informes se envían en el siguiente arranque) y mira
**Firebase Console → Crashlytics**. Quita el botón después.

> En debug no se envía nada a propósito (`setCrashlyticsCollectionEnabled(!kDebugMode)`
> en `main.dart`).

### Añadir la huella SHA-1 a Firebase

Firebase Console → ⚙️ Configuración del proyecto → tu app Android → *Añadir
huella digital* → pega el **SHA-1** de arriba. (Necesario si más adelante usas
Auth/Dynamic Links; para Crashlytics solo no hace falta, pero conviene dejarlo.)

---

## 4. Generar el artefacto para Play

```powershell
flutter build appbundle --release --dart-define-from-file=dart_define.json
```

Salida: `build\app\outputs\bundle\release\app-release.aab`

- Cada subida necesita **`versionCode` distinto y creciente**. Ahora es `1`.
  Para la siguiente sube `version:` en `pubspec.yaml` (p. ej. `1.0.1+2`).
- El AAB incluye el modelo ONNX de recorte (`u2netp.onnx`, ~4,6 MB, licencia
  Apache-2.0 — libre para uso comercial) y las libs nativas de ONNX Runtime.
  Límite de Play para el AAB base: 200 MB → OK.
- El clima ("Outfit del día" y el buscador de ciudad) usa WeatherAPI.com, que
  requiere una clave de API propia (ver `WeatherApiConfig` en
  `lib/services/weather_service.dart`). La clave vive en `dart_define.json`
  (raíz del repo, **ignorado por git**, ver `.gitignore`) y
  `--dart-define-from-file=dart_define.json` la inyecta automáticamente tanto
  en `flutter build appbundle --release` de arriba como en los lanzamientos
  desde VS Code (`.vscode/launch.json`, configuraciones Debug/Profile/Release).
  Si `dart_define.json` no existe o está vacío, esas funciones fallan con un
  aviso legible en vez de romperse en silencio — crea el archivo con
  `{"WEATHER_API_KEY": "tu_clave"}` antes de compilar.

---

## 5. Google Play Console (primera publicación)

1. **Crear cuenta de desarrollador** en <https://play.google.com/console> (25 USD
   pago único). Como es una empresa (gamusinlab), elige cuenta de organización;
   Google pide verificación de identidad/D-U-N-S (puede tardar días).
2. **Crear app**: nombre `Justfit`, idioma por defecto español, tipo App, gratis.
3. **Play App Signing**: acéptalo (viene activado). Subes con la *upload key*
   generada aquí.
4. **Ficha de Play Store**:
   - Descripción corta y larga.
   - Icono 512×512 (tienes `assets/icon/app_icon.png`, reescálalo si hace falta).
   - Gráfico de cabecera 1024×500.
   - Mínimo 2 capturas de teléfono.
5. **Contenido de la app** (todo obligatorio antes de publicar):
   - **Política de privacidad** (URL pública): se publica con **GitHub Pages**
     desde la carpeta `docs/` (`docs/index.html`; fuente en
     `docs/politica-de-privacidad.md`). Pasos para activarla y pegar la URL en
     Play: `docs/README.md`. La app usa **cámara**;
     **Crashlytics** (diagnósticos de fallos); **WeatherAPI.com** (envía la
     ciudad/coordenadas que el usuario elige, nunca GPS); **OpenStreetMap**
     (`tile.openstreetmap.org`, teselas del mapa de ubicación → transmite IP y
     zona del mapa mientras el mapa está abierto). El recorte de fondo corre
     100% en el dispositivo con **ONNX Runtime** (modelo U2-Net embebido); no
     descarga nada tras la instalación. Decláralo todo.
   - **Formulario de seguridad de los datos**: Crashlytics → "Registros de
     fallos" e "Información de diagnóstico". Ubicación aproximada → se comparte
     con WeatherAPI/OpenStreetMap y no se almacena. La cámara/fotos, el recorte
     y las sugerencias de outfit se procesan en el dispositivo y no salen.
   - Clasificación de contenido (cuestionario).
   - App de acceso público, sin anuncios (si es el caso), público objetivo/edad.
   - Permisos: `CAMERA` e `INTERNET`. Sin permisos sensibles adicionales.
6. **Release**:
   - Empieza por **Testing interno** (rápido, sin revisión larga) para validar
     el flujo de subida y Crashlytics en dispositivos reales.
   - Luego **Producción**: crea una versión, sube el `.aab`, notas de la versión,
     revisa el resumen y envía. La primera revisión suele tardar de unas horas
     a varios días.
7. `targetSdkVersion` actual: **36** (Play exige ≥ 35 → OK). `minSdk`: 24.

---

## 6. Pendiente / opcional

- **iOS**: bundle id sigue siendo `com.example...`/el de plantilla y Crashlytics
  no está en el Runner. Cuando toque iOS: `flutterfire configure` con iOS
  marcado + `pod install` + subida de símbolos dSYM.
- **Ofuscación (R8)**: desactivada a propósito (los plugins nativos necesitarían
  reglas keep y Play no lo exige). Si se activa, hay un bloque comentado en
  `android/app/build.gradle.kts` y habrá que subir el `mapping.txt` a Crashlytics.
- **Avisos KGP**: varios plugins (camera, firebase) aún aplican el Kotlin
  Gradle Plugin a la antigua. Solo son *warnings*; se irán arreglando al
  actualizar plugins.
