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

// Configure Tuist integration using the Tuist Gradle Plugin.
// The plugin will execute `tuist cache config` to get the cache configuration
// and automatically refresh credentials when they expire.
//
// plugins {
//     id("dev.tuist") version "0.1.0"
// }
//
// tuist {
//     fullHandle = "account/project"
//
//     buildCache {
//         enabled = true
//         push = true
//     }
// }

// For e2e testing, we use environment variables directly
buildCache {
    remote<HttpBuildCache> {
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
