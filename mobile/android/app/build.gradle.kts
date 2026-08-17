import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Yayın anahtarı bilgileri depoya girmiyor; key.properties dosyasından
// okunuyor (bkz. android/key.properties.example).
//
// Bu dosya neden önemli: APK'nın imzası değişirse Android güncellemeyi
// reddediyor, uygulamayı kaldırıp kurmak gerekiyor ve kaldırma
// kullanıcının bütün eserlerini siliyor. Sabit bir anahtarla imzalanan
// sürümler eskisinin üstüne kurulabiliyor ve veri korunuyor.
val anahtarDosyasi = rootProject.file("key.properties")
val anahtar = Properties().apply {
    if (anahtarDosyasi.exists()) {
        anahtarDosyasi.inputStream().use { load(it) }
    }
}
val yayinAnahtariVar = anahtar.getProperty("storeFile") != null

android {
    namespace = "com.example.ebru_ai_wallpaper"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications, eski Android sürümlerinde de
        // çalışabilmek için bu dönüşümü zorunlu kılıyor.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.ebru_ai_wallpaper"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (yayinAnahtariVar) {
            create("yayin") {
                storeFile = file(anahtar.getProperty("storeFile"))
                storePassword = anahtar.getProperty("storePassword")
                keyAlias = anahtar.getProperty("keyAlias")
                keyPassword = anahtar.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // key.properties varsa kalıcı yayın anahtarı kullanılıyor.
            // Yoksa debug anahtarına düşülüyor ki derleme yine çalışsın —
            // ama o durumda imza sabit değil, güncellemeler kullanıcının
            // eserlerini silebilir.
            signingConfig = if (yayinAnahtariVar) {
                signingConfigs.getByName("yayin")
            } else {
                logger.warn(
                    "UYARI: key.properties yok, release APK debug " +
                    "anahtariyla imzalaniyor. Bu APK'yi dagitirsan " +
                    "sonraki guncellemeler kullanicinin eserlerini silebilir."
                )
                signingConfigs.getByName("debug")
            }

            // R8 kod küçültmesi kapalı: açıkken uygulama açılışta
            // çöküyordu (eklentilerin yansımayla eriştiği sınıflar
            // budanıyor). APK biraz daha büyük oluyor ama çalışıyor.
            // Tekrar açmak istersen proguard-rules.pro hazır duruyor.
            isMinifyEnabled = false
            isShrinkResources = false

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
