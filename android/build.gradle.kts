allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// El plugin `onnxruntime` (1.4.1) fija `compileSdkVersion 33` en su propio
// build.gradle, por debajo del 34 que exigen dependencias transitivas de la
// app (androidx.exifinterface), y AGP aborta la build por ese desajuste.
// Hasta que se corrija upstream se le fuerza el mismo compileSdk que usa la
// app, `flutter.compileSdkVersion` (36 en Flutter 3.44).
//
// Se invoca de forma dinámica con `withGroovyBuilder` para no tener que
// añadir los tipos de AGP al classpath de este build.gradle.kts, y se limita
// a ese subproyecto para no tocar la configuración del resto de plugins.
subprojects {
    if (name == "onnxruntime") {
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder {
                "compileSdkVersion"(36)
            }
        }
    }
}

// `camera_android_camerax` compila contra `camera-core` 1.5.x, que anota
// campos con `@org.jspecify.annotations.NonNull` (anotación TYPE_USE) cuyo
// tipo procede de `androidx.concurrent:concurrent-futures`
// (`CallbackToFutureAdapter.Completer`). javac necesita ESAS clases y las de
// jspecify en el classpath de compilación solo para poder LEER las
// anotaciones, aunque el módulo no las use directamente; `camera-core` no las
// expone con scope `api`, así que se inyectan aquí en el módulo del plugin.
// Sin esto, `flutter build apk --release` falla en
// `:camera_android_camerax:compileReleaseJavaWithJavac` con
// "class file for androidx.concurrent.futures.CallbackToFutureAdapter not found".
subprojects {
    if (name == "camera_android_camerax") {
        afterEvaluate {
            dependencies {
                add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
                add("implementation", "org.jspecify:jspecify:1.0.0")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
