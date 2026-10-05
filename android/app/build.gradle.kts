plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de la versión release.
// Si existen las variables de entorno CASSAFORTE_KEYSTORE_PATH,
// CASSAFORTE_KEYSTORE_PASSWORD, CASSAFORTE_KEY_ALIAS y CASSAFORTE_KEY_PASSWORD
// (en GitHub Actions se crean a partir de secretos), se firma con esa clave
// propia. Si no, se usa la clave de depuración, válida solo para pruebas.
// Nunca se guarda ninguna clave en el repositorio.
val releaseKeystorePath: String? = System.getenv("CASSAFORTE_KEYSTORE_PATH")
val hasReleaseKey = !releaseKeystorePath.isNullOrBlank() && file(releaseKeystorePath).exists()

android {
    namespace = "io.github.gmatiascr62.cassaforte"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.gmatiascr62.cassaforte"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = System.getenv("CASSAFORTE_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CASSAFORTE_KEY_ALIAS")
                keyPassword = System.getenv("CASSAFORTE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
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
