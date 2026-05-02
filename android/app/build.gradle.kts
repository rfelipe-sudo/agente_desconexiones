import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Leer secretos desde local.properties (nunca commitear este archivo)
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "com.creacionestecnologicas.agente_desconexiones"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.creacionestecnologicas.agente_desconexiones"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // ONNX Runtime clases en DEX primario (evita ClassNotFoundException desde hilos JNI nativos)
        multiDexKeepProguard = file("multidex-keep.pro")
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
        // Inyectar secretos en BuildConfig para todas las variantes
        forEach {
            it.buildConfigField("String", "NYQUIST_USER",  "\"${localProps.getProperty("nyquist.user",  "")}\"")
            it.buildConfigField("String", "NYQUIST_PASS",  "\"${localProps.getProperty("nyquist.pass",  "")}\"")
            it.buildConfigField("String", "S3_ACCESS_KEY", "\"${localProps.getProperty("s3.access_key", "")}\"")
            it.buildConfigField("String", "S3_SECRET_KEY", "\"${localProps.getProperty("s3.secret_key", "")}\"")
            it.buildConfigField("String", "S3_BUCKET",     "\"${localProps.getProperty("s3.bucket",     "")}\"")
            it.buildConfigField("String", "S3_REGION",     "\"${localProps.getProperty("s3.region",     "us-east-1")}\"")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    // Los modelos ONNX no deben comprimirse
    aaptOptions {
        noCompress("onnx", "onnx.data")
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // ── Asistente Visual CTO (turing) ──────────────────────────────────────
    // CameraX
    val cameraxVersion = "1.3.4"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")

    // ONNX Runtime (modelos YOLO + ConvNeXt)
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.18.0")

    // HTTP (resultados Kepler / Nyquist)
    implementation("com.squareup.okhttp3:okhttp:4.12.0")

    // Corrutinas
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // WorkManager (subida de fotos a S3 en background)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // AWS S3
    implementation("com.amazonaws:aws-android-sdk-core:2.77.0")
    implementation("com.amazonaws:aws-android-sdk-s3:2.77.0")

    // AppCompat + ConstraintLayout (necesario para las Activities nativas de turing)
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")

    // MultiDex — necesario para MultiDexApplication y para ClassLoader correcto en hilos JNI
    implementation("androidx.multidex:multidex:2.0.1")

    // Guava / ListenableFuture (requerido por CameraX en tiempo de compilación)
    implementation("com.google.guava:guava:32.1.3-android")
}
