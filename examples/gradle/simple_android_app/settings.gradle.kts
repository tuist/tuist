pluginManagement {
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

// Configure Gradle build cache with Tuist
// Option 1: Using environment variables (for CI or manual setup)
// Option 2: Using the Tuist Gradle Plugin (recommended for local development)
//
// To use the plugin, add to your settings.gradle.kts:
//   plugins {
//       id("dev.tuist.build-cache") version "0.1.0"
//   }
//   tuistBuildCache {
//       fullHandle = "account/project"
//   }

buildCache {
    remote<HttpBuildCache> {
        // Cache endpoint URL from TUIST_CACHE_URL environment variable
        // For local development: http://localhost:8181/api/cache/gradle
        // For production: https://cache.tuist.dev/api/cache/gradle
        val cacheUrl = System.getenv("TUIST_CACHE_URL") ?: "http://localhost:8181/api/cache/gradle"
        val accountHandle = System.getenv("TUIST_ACCOUNT_HANDLE") ?: "tuist"
        val projectHandle = System.getenv("TUIST_PROJECT_HANDLE") ?: "gradle"

        url = uri("$cacheUrl?account_handle=$accountHandle&project_handle=$projectHandle")
        credentials {
            username = "tuist"
            password = System.getenv("TUIST_TOKEN") ?: ""
        }
        isPush = true
        isAllowInsecureProtocol = true
    }
}
