// 添加以下导入
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    val keystoreProperties = Properties().apply {
        val keystorePropertiesFile = rootProject.file("./keystore.properties")
        println("属性文件路径: ${keystorePropertiesFile.absolutePath}") // 打印路径
        if (keystorePropertiesFile.exists()) {
            load(FileInputStream(keystorePropertiesFile))
            println("加载的属性: $this") // 打印所有属性
        } else {
            throw GradleException("keystore.properties 文件未找到")
        }
    }

    signingConfigs {
        create("release") {  // 使用 create 方法
            storeFile = file(keystoreProperties.getProperty("storeFile") ?: throw GradleException("storeFile 未定义"))
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }
    namespace = "com.example.qf_controller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.qf_controller"
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
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
