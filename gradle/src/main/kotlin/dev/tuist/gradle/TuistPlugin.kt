package dev.tuist.gradle

import org.gradle.api.Action
import org.gradle.api.Plugin
import org.gradle.api.initialization.Settings
import org.gradle.api.logging.Logger
import org.gradle.api.logging.Logging

data class TuistGradleConfig(
    val url: String,
    val project: String?,
    val uploadInBackground: Boolean? = null,
    val testQuarantineEnabled: Boolean? = null
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
        configureTestInsights(settings, extension)
    }

    private fun configureBuildInsights(settings: Settings, extension: TuistExtension) {
        val project = extension.project.ifBlank { null }
        settings.gradle.rootProject {
            extensions.extraProperties.set(TuistGradleConfig.EXTRA_PROPERTY_KEY, TuistGradleConfig(
                url = extension.url,
                project = project,
                uploadInBackground = extension.uploadInBackground,
                testQuarantineEnabled = extension.testQuarantine.enabled
            ))
            pluginManager.apply(TuistBuildInsightsPlugin::class.java)
            val projectLabel = project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Build insights configured for $projectLabel")
        }
    }

    private fun configureTestInsights(settings: Settings, extension: TuistExtension) {
        val project = extension.project.ifBlank { null }
        settings.gradle.rootProject {
            pluginManager.apply(TuistTestInsightsPlugin::class.java)
            val projectLabel = project ?: "(from tuist.toml)"
            logger.lifecycle("Tuist: Test insights configured for $projectLabel")
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

open class TuistExtension {
    var project: String = ""

    @Deprecated("No longer used. The plugin resolves auth natively without the Tuist CLI.")
    var executablePath: String? = null

    var url: String = "https://tuist.dev"

    var uploadInBackground: Boolean? = null

    val buildCache: BuildCacheExtension = BuildCacheExtension()

    fun buildCache(action: Action<BuildCacheExtension>) {
        action.execute(buildCache)
    }

    val testQuarantine: TestQuarantineExtension = TestQuarantineExtension()

    fun testQuarantine(action: Action<TestQuarantineExtension>) {
        action.execute(testQuarantine)
    }
}

open class BuildCacheExtension {
    var enabled: Boolean = true
    var push: Boolean = true
    var allowInsecureProtocol: Boolean = false
}

open class TestQuarantineExtension {
    var enabled: Boolean? = null
}
