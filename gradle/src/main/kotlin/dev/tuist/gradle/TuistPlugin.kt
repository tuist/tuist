package dev.tuist.gradle

import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.api.logging.Logger
import org.gradle.api.logging.Logging

/**
 * Main Tuist Gradle Settings Plugin.
 *
 * This plugin integrates Gradle projects with Tuist services including
 * remote build caching and analytics.
 *
 * Usage in settings.gradle.kts:
 * ```
 * plugins {
 *     id("dev.tuist") version "0.1.0"
 * }
 *
 * tuist {
 *     fullHandle = "account/project"
 *
 *     buildCache {
 *         enabled = true
 *         push = true
 *     }
 * }
 * ```
 */
class TuistPlugin : Plugin<Settings> {

    private val logger: Logger = Logging.getLogger(TuistPlugin::class.java)

    override fun apply(settings: Settings) {
        val extension = settings.extensions.create(
            "tuist",
            TuistExtension::class.java
        )

        // Register the custom build cache type
        settings.buildCache.registerBuildCacheService(
            TuistBuildCache::class.java,
            TuistBuildCacheServiceFactory::class.java
        )

        settings.gradle.settingsEvaluated {
            configure(settings, extension)
        }
    }

    private fun configure(settings: Settings, extension: TuistExtension) {
        val fullHandle = extension.fullHandle
        if (fullHandle.isBlank()) {
            logger.warn("Tuist: fullHandle not configured. Tuist features will be disabled.")
            return
        }

        configureBuildCache(settings, extension)
        configureBuildInsights(settings, extension)
    }

    private fun configureBuildInsights(settings: Settings, extension: TuistExtension) {
        if (!extension.buildInsights.enabled) {
            logger.info("Tuist: Build insights is disabled.")
            return
        }

        settings.gradle.rootProject {
            extensions.extraProperties.set("tuist.serverUrl", extension.serverUrl)
            extensions.extraProperties.set("tuist.fullHandle", extension.fullHandle)
            extensions.extraProperties.set("tuist.executablePath", extension.executablePath ?: "tuist")
            pluginManager.apply(TuistBuildInsightsPlugin::class.java)
            logger.lifecycle("Tuist: Build insights configured for ${extension.fullHandle}")
        }
    }

    private fun configureBuildCache(settings: Settings, extension: TuistExtension) {
        val buildCacheConfig = extension.buildCache
        if (!buildCacheConfig.enabled) {
            logger.info("Tuist: Build cache is disabled.")
            return
        }

        settings.buildCache {
            remote(TuistBuildCache::class.java) {
                this.fullHandle = extension.fullHandle
                this.executablePath = extension.executablePath
                this.serverUrl = extension.serverUrl
                isPush = buildCacheConfig.push
                this.allowInsecureProtocol = buildCacheConfig.allowInsecureProtocol
            }
        }

        settings.gradle.rootProject {
            logger.lifecycle("Tuist: Remote build cache configured for ${extension.fullHandle}")
        }
    }
}

/**
 * Main extension for configuring Tuist integration.
 */
open class TuistExtension {
    /**
     * The full handle of the project in format "account/project".
     * This is required for all Tuist features.
     */
    var fullHandle: String = ""

    /**
     * Path to the tuist executable. When null, the plugin will look for
     * 'tuist' in the system PATH.
     */
    var executablePath: String? = null

    /**
     * The Tuist server URL. Defaults to https://tuist.dev.
     */
    var serverUrl: String = "https://tuist.dev"

    /**
     * Build cache configuration.
     */
    val buildCache: BuildCacheExtension = BuildCacheExtension()

    /**
     * Build insights configuration.
     */
    val buildInsights: BuildInsightsExtension = BuildInsightsExtension()

    /**
     * Configure build cache settings.
     */
    fun buildCache(configure: BuildCacheExtension.() -> Unit) {
        buildCache.configure()
    }

    /**
     * Configure build insights settings.
     */
    fun buildInsights(configure: BuildInsightsExtension.() -> Unit) {
        buildInsights.configure()
    }
}

/**
 * Configuration for Tuist build cache feature.
 */
open class BuildCacheExtension {
    /**
     * Whether the build cache feature is enabled. Defaults to true.
     */
    var enabled: Boolean = true

    /**
     * Whether to push build outputs to the remote cache. Defaults to true.
     */
    var push: Boolean = true

    /**
     * Whether to allow insecure HTTP connections. Defaults to false.
     */
    var allowInsecureProtocol: Boolean = false
}

/**
 * Configuration for Tuist build insights feature.
 */
open class BuildInsightsExtension {
    /**
     * Whether the build insights feature is enabled. Defaults to true.
     */
    var enabled: Boolean = true
}
