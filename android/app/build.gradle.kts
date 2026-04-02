plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.docscanner"
    compileSdk = flutter.compileSdkVersion
    // Pin to a valid local NDK install. The Flutter-default 28.2 folder on this
    // machine is incomplete and missing source.properties, which breaks Gradle
    // during project configuration.
    ndkVersion = "28.0.12916984"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.docscanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24 // Raised to 24 for CameraX and OpenCV compatibility
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Enable view binding for easier UI work
    buildFeatures {
        viewBinding = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    // CameraX - Camera control with frame analysis
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")

    // EXIF - Read image orientation metadata for correct rotation handling
    implementation("androidx.exifinterface:exifinterface:1.3.7")

    // OpenCV - Image processing, edge detection, perspective correction
    implementation("org.opencv:opencv:4.10.0")

    // ML Kit - Text recognition (OCR)
    implementation("com.google.mlkit:text-recognition:16.0.1")

    // Kotlin coroutines for async operations
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
}
