pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
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

rootProject.name = "Tuist"

plugins {
    id("dev.tuist") version "0.22.0"
}

tuist {
    coverage {
        enabled = true
    }
}

buildCache {
    local {
        isEnabled = System.getenv("CI") == null
    }
}

include(":app")
