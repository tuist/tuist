pluginManagement {
    includeBuild("../../../gradle")
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SimpleAndroidApp"
include(":app")

plugins {
    id("dev.tuist") version "0.1.0"
}

tuist {
    fullHandle = "tuist/android-app"
    executablePath = System.getenv("TUIST_EXECUTABLE")
    serverUrl = System.getenv("TUIST_SERVER_URL") ?: "https://tuist.dev"

    buildCache {
        enabled = true
        push = true
        allowInsecureProtocol = true
    }

    buildInsights {
        enabled = true
    }
}
