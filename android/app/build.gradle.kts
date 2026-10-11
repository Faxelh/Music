plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.faxel.music"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.faxel.music"
        minSdk = 26
        targetSdk = 34
        // Numéro de version = numéro de la compilation GitHub (minutes depuis 1970) :
        // chaque APK est plus récent que le précédent, l'app sait proposer la mise à jour.
        versionCode = (System.getenv("APP_BUILD") ?: "1").toInt()
        versionName = System.getenv("APP_VERSION") ?: "2026.1.0"
    }

    signingConfigs {
        // Toujours la même clé : les nouvelles versions s'installent par-dessus l'ancienne.
        create("music") {
            storeFile = file("music.jks")
            storePassword = "musicfaxel"
            keyAlias = "music"
            keyPassword = "musicfaxel"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("music")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    lint {
        abortOnError = false
        checkReleaseBuilds = false
    }
    androidResources {
        generateLocaleConfig = false
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.03")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.6")
    implementation("androidx.media3:media3-exoplayer:1.4.1")
    implementation("androidx.media3:media3-session:1.4.1")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
