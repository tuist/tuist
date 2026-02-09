package dev.tuist.gradle

import com.google.gson.Gson
import org.gradle.api.logging.Logging
import org.gradle.caching.BuildCacheEntryReader
import org.gradle.caching.BuildCacheEntryWriter
import org.gradle.caching.BuildCacheException
import org.gradle.caching.BuildCacheKey
import org.gradle.caching.BuildCacheService
import org.gradle.caching.BuildCacheServiceFactory
import org.gradle.caching.configuration.AbstractBuildCache
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URI

/**
 * Minimum required Tuist CLI version for this plugin.
 */
object TuistVersion {
    const val MINIMUM_REQUIRED = "4.31.0"

    fun parseVersion(version: String): List<Int>? {
        return try {
            version.trim().split(".").map { it.toInt() }
        } catch (e: Exception) {
            null
        }
    }

    fun isVersionSufficient(current: String, minimum: String = MINIMUM_REQUIRED): Boolean {
        val currentParts = parseVersion(current) ?: return false
        val minimumParts = parseVersion(minimum) ?: return false

        for (i in 0 until maxOf(currentParts.size, minimumParts.size)) {
            val currentPart = currentParts.getOrElse(i) { 0 }
            val minimumPart = minimumParts.getOrElse(i) { 0 }

            if (currentPart > minimumPart) return true
            if (currentPart < minimumPart) return false
        }
        return true
    }
}

/**
 * Build cache configuration type for Tuist.
 */
open class TuistBuildCache : AbstractBuildCache() {
    var project: String = ""
    var executablePath: String? = null
    var url: String? = null
    var allowInsecureProtocol: Boolean = false
}

/**
 * Factory that creates TuistBuildCacheService instances.
 */
class TuistBuildCacheServiceFactory : BuildCacheServiceFactory<TuistBuildCache> {
    private val logger = Logging.getLogger(TuistBuildCacheServiceFactory::class.java)

    override fun createBuildCacheService(
        configuration: TuistBuildCache,
        describer: BuildCacheServiceFactory.Describer
    ): BuildCacheService {
        describer
            .type("Tuist")
            .config("project", configuration.project)

        val resolvedCommand = resolveCommand(configuration)

        validateTuistVersion(resolvedCommand)

        val configurationProvider = TuistCommandConfigurationProvider(
            project = configuration.project,
            command = resolvedCommand,
            url = configuration.url
        )

        val httpClient = TuistHttpClient(configurationProvider)

        return TuistBuildCacheService(
            httpClient = httpClient,
            isPushEnabled = configuration.isPush
        )
    }

    private fun resolveCommand(configuration: TuistBuildCache): List<String> {
        return listOf(configuration.executablePath ?: "tuist")
    }

    private fun validateTuistVersion(command: List<String>) {
        val version = getTuistVersion(command)
        if (version == null) {
            // Version check failed, but the executable exists.
            // This can happen when running in a Tuist project directory where
            // dependencies haven't been installed. Log a warning but don't fail.
            logger.warn("Tuist: Could not determine Tuist version. Proceeding without version validation.")
            return
        }

        if (!TuistVersion.isVersionSufficient(version)) {
            throw BuildCacheException(
                "Tuist version $version is not supported. " +
                "Please update to version ${TuistVersion.MINIMUM_REQUIRED} or later. " +
                "Run 'tuist update' or visit https://docs.tuist.dev/guides/quick-start/install-tuist for installation instructions."
            )
        }
    }

    private fun getTuistVersion(command: List<String>): String? {
        return try {
            val process = ProcessBuilder(command + "version")
                .redirectErrorStream(true)
                .start()

            val output = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                reader.readLine()?.trim() ?: ""
            }

            val exitCode = process.waitFor()
            if (exitCode == 0) output else null
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Provides cache configuration, typically by running `tuist cache config`.
 */
interface ConfigurationProvider {
    fun getConfiguration(forceRefresh: Boolean = false): TuistCacheConfiguration
}

/**
 * Default configuration provider that runs `tuist cache config` command.
 */
class TuistCommandConfigurationProvider(
    private val project: String,
    private val command: List<String>,
    private val url: String? = null
) : ConfigurationProvider {

    override fun getConfiguration(forceRefresh: Boolean): TuistCacheConfiguration {
        val baseArgs = buildList {
            addAll(listOf("cache", "config", project, "--json"))
            if (!url.isNullOrBlank()) {
                addAll(listOf("--url", url))
            }
        }
        val args = if (forceRefresh) baseArgs + "--force-refresh" else baseArgs
        val fullCommand = command + args

        // Create a unique temp directory to avoid tuist detecting any project context.
        val tempDir = java.nio.file.Files.createTempDirectory("tuist-gradle-").toFile()
        try {
            val processBuilder = ProcessBuilder(fullCommand)
                .directory(tempDir)
                .redirectErrorStream(false)

            // Clear environment variables that might leak project context to tuist
            val env = processBuilder.environment()
            env.remove("PWD")
            env.remove("TUIST_CONFIG_PATH")
            env.remove("TUIST_CURRENT_DIRECTORY")

            val process = processBuilder.start()

            val output = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                reader.readText()
            }

            val stderr = BufferedReader(InputStreamReader(process.errorStream)).use { reader ->
                reader.readText()
            }

            val exitCode = process.waitFor()
            if (exitCode != 0) {
                val message = stderr.ifBlank { "exit code $exitCode" }
                throw RuntimeException("tuist cache config failed: $message")
            }

            return Gson().fromJson(output, TuistCacheConfiguration::class.java)
                ?: throw RuntimeException("tuist cache config returned invalid JSON")
        } finally {
            tempDir.delete()
        }
    }
}

/**
 * Custom BuildCacheService that handles authentication and automatic token refresh.
 *
 * When a 401 Unauthorized response is received, this service automatically
 * refreshes the configuration and retries the request.
 */
class TuistBuildCacheService(
    private val httpClient: TuistHttpClient,
    private val isPushEnabled: Boolean
) : BuildCacheService {

    override fun load(key: BuildCacheKey, reader: BuildCacheEntryReader): Boolean {
        return httpClient.execute { config ->
            val url = buildCacheUrl(config, key.hashCode)
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"

            when (connection.responseCode) {
                HttpURLConnection.HTTP_OK -> {
                    connection.inputStream.use { input ->
                        reader.readFrom(input)
                    }
                    true
                }
                HttpURLConnection.HTTP_NOT_FOUND -> false
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> throw BuildCacheException(
                    "Loading cache entry failed with status ${connection.responseCode}"
                )
            }
        }
    }

    override fun store(key: BuildCacheKey, writer: BuildCacheEntryWriter) {
        if (!isPushEnabled) return

        httpClient.execute<Unit> { config ->
            val url = buildCacheUrl(config, key.hashCode)
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "PUT"
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/octet-stream")

            connection.outputStream.use { output ->
                writer.writeTo(output)
            }

            when (connection.responseCode) {
                HttpURLConnection.HTTP_OK, HttpURLConnection.HTTP_CREATED, HttpURLConnection.HTTP_NO_CONTENT -> {}
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> throw BuildCacheException(
                    "Storing cache entry failed with status ${connection.responseCode}"
                )
            }
        }
    }

    override fun close() {
        // No resources to clean up
    }

    internal fun buildCacheUrl(config: TuistCacheConfiguration, cacheKey: String): URI {
        val baseUri = URI.create(config.url.trimEnd('/'))
        return URI(
            baseUri.scheme,
            baseUri.userInfo,
            baseUri.host,
            baseUri.port,
            "${baseUri.path}/api/cache/gradle/$cacheKey",
            "account_handle=${config.accountHandle}&project_handle=${config.projectHandle}",
            null
        )
    }
}

/**
 * Data class representing the cache configuration returned by `tuist cache config --json`.
 */
data class TuistCacheConfiguration(
    val url: String,
    val token: String,
    @com.google.gson.annotations.SerializedName("account_handle")
    val accountHandle: String,
    @com.google.gson.annotations.SerializedName("project_handle")
    val projectHandle: String
)
