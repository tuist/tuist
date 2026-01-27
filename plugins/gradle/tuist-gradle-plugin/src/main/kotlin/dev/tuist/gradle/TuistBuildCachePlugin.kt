package dev.tuist.gradle

import com.google.gson.Gson
import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.caching.http.HttpBuildCache
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.URI

/**
 * Gradle Settings Plugin that configures remote build cache with Tuist.
 *
 * This plugin executes `tuist cache config` to retrieve the cache endpoint
 * and authentication token, then configures Gradle's HttpBuildCache accordingly.
 *
 * Usage in settings.gradle.kts:
 * ```
 * plugins {
 *     id("dev.tuist.build-cache") version "0.1.0"
 * }
 *
 * tuistBuildCache {
 *     fullHandle = "account/project"
 * }
 * ```
 */
class TuistBuildCachePlugin : Plugin<Settings> {

    override fun apply(settings: Settings) {
        val extension = settings.extensions.create(
            "tuistBuildCache",
            TuistBuildCacheExtension::class.java
        )

        settings.gradle.settingsEvaluated {
            configureBuildCache(settings, extension)
        }
    }

    private fun configureBuildCache(settings: Settings, extension: TuistBuildCacheExtension) {
        val config = getCacheConfiguration(extension)
            ?: run {
                settings.gradle.rootProject {
                    logger.warn("Tuist: Failed to get cache configuration. Remote build cache not configured.")
                }
                return
            }

        settings.buildCache {
            remote(HttpBuildCache::class.java) {
                url = URI.create(buildCacheUrl(config, extension))
                credentials {
                    username = "tuist"
                    password = config.token
                }
                isPush = extension.push
                isAllowInsecureProtocol = extension.allowInsecureProtocol
            }
        }

        settings.gradle.rootProject {
            logger.lifecycle("Tuist: Remote build cache configured at ${config.url}")
        }
    }

    private fun buildCacheUrl(config: TuistCacheConfiguration, extension: TuistBuildCacheExtension): String {
        val baseUrl = config.url.trimEnd('/')
        return "$baseUrl/api/cache/gradle?account_handle=${config.accountHandle}&project_handle=${config.projectHandle}"
    }

    private fun getCacheConfiguration(extension: TuistBuildCacheExtension): TuistCacheConfiguration? {
        // First, try environment variables as fallback
        val envEndpoint = System.getenv("TUIST_CACHE_URL")
        val envToken = System.getenv("TUIST_TOKEN")

        if (!envEndpoint.isNullOrBlank() && !envToken.isNullOrBlank()) {
            val fullHandle = extension.fullHandle
            val parts = fullHandle.split("/", limit = 2)
            return TuistCacheConfiguration(
                url = envEndpoint,
                token = envToken,
                accountHandle = parts.getOrElse(0) { "" },
                projectHandle = parts.getOrElse(1) { "" }
            )
        }

        // Try to execute tuist command
        val fullHandle = extension.fullHandle
        if (fullHandle.isBlank()) {
            return null
        }

        return try {
            executeTuistCommand(fullHandle, extension.tuistPath)
        } catch (e: Exception) {
            null
        }
    }

    private fun executeTuistCommand(fullHandle: String, tuistPath: String): TuistCacheConfiguration? {
        val command = listOf(tuistPath, "cache", "config", fullHandle, "--json")

        val process = ProcessBuilder(command)
            .redirectErrorStream(false)
            .start()

        val output = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
            reader.readText()
        }

        val exitCode = process.waitFor()
        if (exitCode != 0) {
            return null
        }

        return try {
            Gson().fromJson(output, TuistCacheConfiguration::class.java)
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Extension for configuring the Tuist build cache plugin.
 */
open class TuistBuildCacheExtension {
    /**
     * The full handle of the project in format "account/project".
     */
    var fullHandle: String = ""

    /**
     * Path to the tuist executable. Defaults to "tuist".
     */
    var tuistPath: String = "tuist"

    /**
     * Whether to push build outputs to the remote cache.
     */
    var push: Boolean = true

    /**
     * Whether to allow insecure HTTP connections.
     */
    var allowInsecureProtocol: Boolean = false
}

/**
 * Data class representing the cache configuration returned by `tuist cache config --json`.
 */
data class TuistCacheConfiguration(
    val url: String,
    val token: String,
    val accountHandle: String,
    val projectHandle: String
)
