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
 *     // Optional: if not set, the project is read from tuist.toml
 *     // project = "account/project"
 *
 *     uploadInBackground = true // default: true locally, false on CI
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
    val project: String?,
    val executablePath: String,
    val uploadInBackground: Boolean? = null
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
        configureBuildCache(settings, extension)
        configureBuildInsights(settings, extension)
    }

    private fun configureBuildInsights(settings: Settings, extension: TuistExtension) {
        val project = extension.project.ifBlank { null }
        settings.gradle.rootProject {
            extensions.extraProperties.set(TuistGradleConfig.EXTRA_PROPERTY_KEY, TuistGradleConfig(
                url = extension.url,
                project = project,
                executablePath = extension.executablePath ?: "tuist",
                uploadInBackground = extension.uploadInBackground
            ))
            pluginManager.apply(TuistBuildInsightsPlugin::class.java)
            val projectLabel = project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Build insights configured for $projectLabel")
        }
    }

    private fun configureBuildCache(settings: Settings, extension: TuistExtension) {
        val buildCacheConfig = extension.buildCache
        if (!buildCacheConfig.enabled) {
            logger.info("Tuist: Build cache is disabled.")
            return
        }

        val project = extension.project.ifBlank { null }

        settings.buildCache {
            remote(TuistBuildCache::class.java) {
                this.project = project
                this.executablePath = extension.executablePath
                this.url = extension.url
                isPush = buildCacheConfig.push
                this.allowInsecureProtocol = buildCacheConfig.allowInsecureProtocol
            }
        }

        settings.gradle.rootProject {
            val projectLabel = project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Remote build cache configured for $projectLabel")
        }
    }
}

/**
 * Main extension for configuring Tuist integration.
 */
open class TuistExtension {
    /**
     * The project identifier in format "account/project".
     * If not set, the plugin reads it from the tuist.toml file in the project root.
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
     * Whether to upload build insights in the background. When null (default),
     * the upload runs in the background for local builds and in the foreground on CI
     * to ensure it completes before ephemeral agents exit.
     */
    var uploadInBackground: Boolean? = null

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

