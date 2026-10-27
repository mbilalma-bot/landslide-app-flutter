plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.landslide_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.landslide_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.

            // Konfigurasi signing/tanda tangan, id nya yaitu debug, tujuan untuk pengujian, bukan untuk diakses pengguna
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Mengubah nama APK release berdasarkan versi Flutter.
    applicationVariants.all {
        if (buildType.name == "release") {
            outputs.all {
                val output =
                    this as com.android.build.gradle.internal.api.BaseVariantOutputImpl

                output.outputFileName = "LandslideApp-${versionName}.apk"
            }
        }
    }
}

flutter {
    source = "../.."
}
