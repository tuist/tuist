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
 *     project = "account/project"
 *
 *     buildCache {
 *         enabled = true
 *         push = true
 *     }
 * }
 * ```
 */
/**
 * Shared configuration passed from the settings plugin to project-level feature plugins.
 */
data class TuistGradleConfig(
    val url: String,
    val project: String,
    val executablePath: String
) {
    companion object {
        internal const val EXTRA_PROPERTY_KEY = "tuist.config"

        fun from(project: org.gradle.api.Project): TuistGradleConfig? =
            project.extensions.extraProperties.let {
                if (it.has(EXTRA_PROPERTY_KEY)) it.get(EXTRA_PROPERTY_KEY) as? TuistGradleConfig else null
            }
    }
}

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
        val project = extension.project
        if (project.isBlank()) {
            logger.warn("Tuist: project not configured. Tuist features will be disabled.")
            return
        }

        configureBuildCache(settings, extension)
        configureBuildInsights(settings, extension)
    }

    private fun configureBuildInsights(settings: Settings, extension: TuistExtension) {
        settings.gradle.rootProject {
            extensions.extraProperties.set(TuistGradleConfig.EXTRA_PROPERTY_KEY, TuistGradleConfig(
                url = extension.url,
                project = extension.project,
                executablePath = extension.executablePath ?: "tuist"
            ))
            pluginManager.apply(TuistBuildInsightsPlugin::class.java)
            logger.lifecycle("Tuist: Build insights configured for ${extension.project}")
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
                this.project = extension.project
                this.executablePath = extension.executablePath
                this.url = extension.url
                isPush = buildCacheConfig.push
                this.allowInsecureProtocol = buildCacheConfig.allowInsecureProtocol
            }
        }

        settings.gradle.rootProject {
            logger.lifecycle("Tuist: Remote build cache configured for ${extension.project}")
        }
    }
}

/**
 * Main extension for configuring Tuist integration.
 */
open class TuistExtension {
    /**
     * The project identifier in format "account/project".
     * This is required for all Tuist features.
     */
    var project: String = ""

    /**
     * Path to the tuist executable. When null, the plugin will look for
     * 'tuist' in the system PATH.
     */
    var executablePath: String? = null

    /**
     * The base URL that points to the Tuist server. Defaults to https://tuist.dev.
     */
    var url: String = "https://tuist.dev"

    /**
     * Build cache configuration.
     */
    val buildCache: BuildCacheExtension = BuildCacheExtension()

    /**
     * Configure build cache settings.
     */
    fun buildCache(configure: BuildCacheExtension.() -> Unit) {
        buildCache.configure()
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

