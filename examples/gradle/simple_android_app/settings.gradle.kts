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
    fullHandle = "tuist/tuist"
    executablePath = System.getenv("TUIST_EXECUTABLE")

    buildCache {
        enabled = true
        push = true
        allowInsecureProtocol = true
    }
}
