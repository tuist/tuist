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
    id("dev.tuist") version "0.2.1"
}

tuist {
    executablePath = System.getenv("TUIST_EXECUTABLE")
    url = System.getenv("TUIST_SERVER_URL") ?: "https://tuist.dev"

    buildCache {
        enabled = true
        push = true
        allowInsecureProtocol = true
    }
}
