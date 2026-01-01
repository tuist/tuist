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

buildCache {
    remote<HttpBuildCache> {
        // For local development, use: http://localhost:8080/api/cache/gradle/tuist/gradle/
        // For production, use: https://tuist.dev/api/cache/gradle/{account}/{project}/
        url = uri(System.getenv("TUIST_CACHE_URL") ?: "http://localhost:8080/api/cache/gradle/tuist/gradle/")
        credentials {
            username = "token"
            // Token format: tuist_{token_id}_gradlecachedevtoken (from seed)
            password = System.getenv("TUIST_TOKEN") ?: ""
        }
        isPush = true
        // Required for local dev with http:// (not needed for production https)
        isAllowInsecureProtocol = true
    }
}
