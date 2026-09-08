import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Los plugins de Firebase solo se aplican cuando existe google-services.json
// (lo genera `flutterfire configure`). Así el proyecto compila también antes
// de configurar Firebase, y Crashlytics se activa solo en cuanto aparece el
// fichero — sin tocar más este build.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.warn(
        "google-services.json no encontrado en android/app/ — Firebase/Crashlytics " +
        "desactivado en esta build. Ejecuta `flutterfire configure`.",
    )
}

// Credenciales de firma de release. Viven en android/key.properties (fuera de
// git). Si el fichero no existe (p. ej. un clon recién hecho), el release cae a
// la clave de debug para que `flutter run --release` siga funcionando en local.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gamusinlab.justfit"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // ID de aplicación definitivo en Google Play (no se puede cambiar una
        // vez publicada la app). Empresa: gamusinlab · app: Justfit.
        applicationId = "com.gamusinlab.justfit"
        // Suelo en API 24 (Android 7.0): cubre las dependencias nativas
        // (Firebase, ONNX Runtime, CameraX) con margen y simplifica el soporte.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Empaqueta las tablas de símbolos de las .so nativas en el AAB
            // para desofuscar crashes/ANR nativos (onnxruntime, ML Kit) en
            // Play Console y Crashlytics. Requiere el SDK "Android SDK
            // Command-line Tools" instalado.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
            // Sin ofuscación/minificación por ahora: los plugins nativos
            // (onnxruntime, ML Kit, CameraX) necesitarían reglas keep propias y
            // Play no exige R8. Así los stack traces de Crashlytics llegan
            // legibles sin subir mapping. Si más adelante se activa:
            //   isMinifyEnabled = true
            //   isShrinkResources = true
            //   proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Ver también el parche a `:camera_android_camerax` en
    // `android/build.gradle.kts`: el error de compilación real ("class file
    // for androidx.concurrent.futures.CallbackToFutureAdapter not found")
    // ocurre en el módulo del plugin, no aquí, así que la corrección de fondo
    // vive allí. Estas dos líneas dejan además las clases en el classpath del
    // módulo de app por si alguna otra ruta de compilación las necesita.
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("org.jspecify:jspecify:1.0.0")
}
