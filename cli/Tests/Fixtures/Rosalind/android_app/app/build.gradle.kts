plugins {
    id("com.android.application")
}

android {
    namespace = "dev.tuist.example"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.tuist.example"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            vcsInfo {
                include = false
            }
        }
    }

    flavorDimensions += "label"

    productFlavors {
        create("referenceLabel") { dimension = "label" }
        create("literalLabel") { dimension = "label" }
        create("noLabel") { dimension = "label" }
    }
}

dependencies {
    implementation(project(":library"))
}
