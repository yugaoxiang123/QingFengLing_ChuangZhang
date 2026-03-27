// Add the following imports
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    val keystorePropertiesFile = rootProject.file("./keystore.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        println("Keystore file path: ${keystorePropertiesFile.absolutePath}")
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        // Avoid printing sensitive information like passwords in build logs
        println("Keystore properties loaded successfully.")
    } else {
        println("Keystore file not found, release will use debug signing for local testing.")
    }
    fun resolveStoreFile(path: String): File {
        val configured = File(path)
        if (configured.isAbsolute) return configured

        // Support both relative-to-android and relative-to-android/app paths.
        val fromAndroidDir = rootProject.file(path)
        if (fromAndroidDir.exists()) return fromAndroidDir

        return project.file(path)
    }
    val storeFileName = keystoreProperties.getProperty("storeFile")
    val resolvedStoreFile = storeFileName?.let { resolveStoreFile(it) }
    val hasReleaseKeystore =
        !storeFileName.isNullOrBlank() &&
            resolvedStoreFile?.exists() == true &&
            !keystoreProperties.getProperty("storePassword").isNullOrBlank() &&
            !keystoreProperties.getProperty("keyAlias").isNullOrBlank() &&
            !keystoreProperties.getProperty("keyPassword").isNullOrBlank()

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = resolvedStoreFile
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }
    namespace = "com.example.qf_controller"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

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
            // Temporary testing setup: sign release build with debug key.
            // IMPORTANT: switch back to "release" before production publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
