plugins {
    id("com.android.application") version "8.7.3"
}

android {
    namespace = "dev.tuist.emulatorsmoke"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.tuist.emulatorsmoke"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }
}
