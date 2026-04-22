package dev.tuist.gradle

import org.gradle.api.Action
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
 *     http {
 *         proxy = false
 *     }
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
    val http: Http,
    val uploadInBackground: Boolean? = null,
    val testQuarantineEnabled: Boolean? = null
) {
    data class Http(val proxy: Boolean)

    companion object {
        internal const val EXTRA_PROPERTY_KEY = "tuist.config"

        fun from(settings: Settings, extension: TuistExtension): TuistGradleConfig =
            TuistGradleConfig(
                url = extension.url,
                project = extension.project.ifBlank { null },
                http = Http(
                    proxy = EnvironmentProxyResolver.resolve(
                        extensionProxy = extension.http.proxy,
                        projectDir = settings.settingsDir
                    )
                ),
                uploadInBackground = extension.uploadInBackground,
                testQuarantineEnabled = extension.testQuarantine.enabled
            )

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

        settings.buildCache.registerBuildCacheService(
            TuistBuildCache::class.java,
            TuistBuildCacheServiceFactory::class.java
        )

        settings.gradle.settingsEvaluated {
            configure(settings, extension)
        }
    }

    private fun configure(settings: Settings, extension: TuistExtension) {
        val config = TuistGradleConfig.from(settings, extension)
        publishSharedConfig(settings, config)
        configureBuildCache(settings, config, extension.buildCache)
        configureBuildInsights(settings, config)
        configureTestInsights(settings, config)
    }

    private fun publishSharedConfig(settings: Settings, config: TuistGradleConfig) {
        settings.gradle.rootProject {
            extensions.extraProperties.set(TuistGradleConfig.EXTRA_PROPERTY_KEY, config)
        }
    }

    private fun configureBuildInsights(settings: Settings, config: TuistGradleConfig) {
        settings.gradle.rootProject {
            pluginManager.apply(TuistBuildInsightsPlugin::class.java)
            val projectLabel = config.project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Build insights configured for $projectLabel")
        }
    }

    private fun configureTestInsights(settings: Settings, config: TuistGradleConfig) {
        settings.gradle.rootProject {
            pluginManager.apply(TuistTestInsightsPlugin::class.java)
            pluginManager.apply(TuistTestShardingPlugin::class.java)
            val projectLabel = config.project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Test insights configured for $projectLabel")
        }
    }

    private fun configureBuildCache(
        settings: Settings,
        config: TuistGradleConfig,
        buildCacheConfig: BuildCacheExtension
    ) {
        if (!buildCacheConfig.enabled) {
            logger.info("Tuist: Build cache is disabled.")
            return
        }

        settings.buildCache {
            remote(TuistBuildCache::class.java) {
                this.project = config.project
                this.url = config.url
                this.projectDir = settings.settingsDir.absolutePath
                this.useEnvironmentProxy = config.http.proxy
                isPush = buildCacheConfig.push
                this.allowInsecureProtocol = buildCacheConfig.allowInsecureProtocol
            }
        }

        settings.gradle.rootProject {
            val projectLabel = config.project ?: "(from tuist.toml)"
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

    @Deprecated("No longer used. The plugin resolves auth natively without the Tuist CLI.")
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
     * HTTP configuration.
     */
    val http: HttpSettings = HttpSettings()

    /**
     * Configure HTTP settings.
     */
    fun http(action: Action<HttpSettings>) {
        action.execute(http)
    }

    /**
     * Build cache configuration.
     */
    val buildCache: BuildCacheExtension = BuildCacheExtension()

    /**
     * Configure build cache settings.
     */
    fun buildCache(action: Action<BuildCacheExtension>) {
        action.execute(buildCache)
    }

    /**
     * Test quarantine configuration.
     */
    val testQuarantine: TestQuarantineExtension = TestQuarantineExtension()

    /**
     * Configure test quarantine settings.
     */
    fun testQuarantine(action: Action<TestQuarantineExtension>) {
        action.execute(testQuarantine)
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
 * Configuration for Tuist's HTTP behavior.
 */
open class HttpSettings {
    /**
     * Whether the plugin should use the proxy defined by `HTTPS_PROXY`/`HTTP_PROXY`.
     * When null (default), the plugin reads `[http].proxy` from `tuist.toml`
     * and otherwise falls back to `true`.
     */
    var proxy: Boolean? = null
}

/**
 * Configuration for test quarantine feature.
 * When enabled, quarantined (flaky) tests are automatically excluded from test runs.
 */
open class TestQuarantineExtension {
    /**
     * Whether test quarantine is enabled. When null (default), quarantine is
     * automatically enabled on CI and disabled for local builds.
     */
    var enabled: Boolean? = null
}
