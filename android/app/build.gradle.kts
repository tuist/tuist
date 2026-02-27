plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.play.publisher)
    alias(libs.plugins.openapi.generator)
}

android {
    namespace = "dev.tuist.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "dev.tuist.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        create("release") {
            val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
                ?: rootProject.file("release.keystore").takeIf { it.exists() }?.absolutePath
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: ""
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "tuist"
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: ""
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("String", "SERVER_URL", "\"https://tuist.dev\"")
            buildConfigField("String", "OAUTH_CLIENT_ID", "\"b3298a92-3deb-4f5e-a526-b7ad324979b5\"")
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
            buildConfigField("String", "SERVER_URL", "\"https://tuist.dev\"")
            buildConfigField("String", "OAUTH_CLIENT_ID", "\"b3298a92-3deb-4f5e-a526-b7ad324979b5\"")
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

    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
    }

    sourceSets["main"].java.srcDir("${layout.buildDirectory.get()}/generated/openapi/src/main/kotlin")
}

play {
    val serviceAccountJsonPath = System.getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
        ?: rootProject.file("service-account.json").takeIf { it.exists() }?.absolutePath
    if (serviceAccountJsonPath != null) {
        serviceAccountCredentials.set(file(serviceAccountJsonPath))
    }
    track.set("internal")
    releaseStatus.set(com.github.triplet.gradle.androidpublisher.ReleaseStatus.DRAFT)
    defaultToAppBundles.set(true)
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.activity.compose)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    debugImplementation(libs.androidx.ui.tooling)

    implementation(libs.androidx.navigation.compose)

    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)

    implementation(libs.retrofit)
    implementation(libs.retrofit.moshi)
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.moshi)
    implementation(libs.moshi.kotlin)
    ksp(libs.moshi.kotlin.codegen)

    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.browser)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.turbine)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.robolectric)
}

openApiGenerate {
    generatorName.set("kotlin")
    inputSpec.set("${rootProject.projectDir}/../cli/Sources/TuistServer/OpenAPI/server.yml")
    outputDir.set("${layout.buildDirectory.get()}/generated/openapi")
    apiPackage.set("dev.tuist.app.api")
    modelPackage.set("dev.tuist.app.api.model")
    configOptions.set(mapOf(
        "library" to "jvm-retrofit2",
        "serializationLibrary" to "moshi",
        "useCoroutines" to "true",
        "enumPropertyNaming" to "original",
    ))
    globalProperties.set(mapOf(
        "models" to "",
        "apis" to "",
    ))
    typeMappings.set(mapOf(
        "number" to "Int",
    ))
    importMappings.set(mapOf(
        "Int" to "kotlin.Int",
    ))
}

tasks.named("preBuild") {
    dependsOn("openApiGenerate")
}
