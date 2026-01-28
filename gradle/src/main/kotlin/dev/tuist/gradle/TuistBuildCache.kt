package dev.tuist.gradle

import com.google.gson.Gson
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
    var fullHandle: String = ""
    var executablePath: String? = null
    var executableCommand: List<String>? = null
    var allowInsecureProtocol: Boolean = false
}

/**
 * Factory that creates TuistBuildCacheService instances.
 */
class TuistBuildCacheServiceFactory : BuildCacheServiceFactory<TuistBuildCache> {
    override fun createBuildCacheService(
        configuration: TuistBuildCache,
        describer: BuildCacheServiceFactory.Describer
    ): BuildCacheService {
        describer
            .type("Tuist")
            .config("fullHandle", configuration.fullHandle)

        val resolvedCommand = resolveCommand(configuration)

        validateTuistVersion(resolvedCommand)

        val configurationProvider = TuistCommandConfigurationProvider(
            fullHandle = configuration.fullHandle,
            command = resolvedCommand
        )

        return TuistBuildCacheService(
            configurationProvider = configurationProvider,
            isPushEnabled = configuration.isPush
        )
    }

    private fun resolveCommand(configuration: TuistBuildCache): List<String> {
        // If executableCommand is provided, use it directly
        configuration.executableCommand?.let { return it }

        // Otherwise, resolve the executable path
        val resolvedPath = configuration.executablePath ?: findTuistInPath()
            ?: throw BuildCacheException(
                "Tuist CLI not found. Please install Tuist (https://docs.tuist.dev/guides/quick-start/install-tuist) " +
                "or set 'executablePath' or 'executableCommand' in the tuist extension."
            )

        return listOf(resolvedPath)
    }

    private fun findTuistInPath(): String? {
        val pathEnv = System.getenv("PATH") ?: return null
        val pathSeparator = System.getProperty("path.separator") ?: ":"
        val executableName = if (System.getProperty("os.name").lowercase().contains("win")) "tuist.exe" else "tuist"

        for (dir in pathEnv.split(pathSeparator)) {
            val file = java.io.File(dir, executableName)
            if (file.exists() && file.canExecute()) {
                return file.absolutePath
            }
        }
        return null
    }

    private fun validateTuistVersion(command: List<String>) {
        val version = getTuistVersion(command)
            ?: throw BuildCacheException(
                "Failed to determine Tuist version. Please ensure Tuist is correctly installed. Command: ${command.joinToString(" ")}"
            )

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
            // Create a unique temp directory to avoid tuist detecting any project context.
            // We need an isolated directory because the system temp dir might be within
            // a directory tree that contains a Tuist project.
            val tempDir = java.nio.file.Files.createTempDirectory("tuist-gradle-").toFile()
            try {
                val process = ProcessBuilder(command + "version")
                    .directory(tempDir)
                    .redirectErrorStream(true)
                    .start()

                val output = BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                    reader.readText().trim()
                }

                val exitCode = process.waitFor()
                if (exitCode == 0) output else null
            } finally {
                tempDir.delete()
            }
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * Provides cache configuration, typically by running `tuist cache config`.
 */
fun interface ConfigurationProvider {
    fun getConfiguration(): TuistCacheConfiguration?
}

/**
 * Default configuration provider that runs `tuist cache config` command.
 */
class TuistCommandConfigurationProvider(
    private val fullHandle: String,
    private val command: List<String>
) : ConfigurationProvider {

    override fun getConfiguration(): TuistCacheConfiguration? {
        val fullCommand = command + listOf("cache", "config", fullHandle, "--json")

        // Create a unique temp directory to avoid tuist detecting any project context.
        val tempDir = java.nio.file.Files.createTempDirectory("tuist-gradle-").toFile()
        try {
            val process = ProcessBuilder(fullCommand)
                .directory(tempDir)
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
    private val configurationProvider: ConfigurationProvider,
    private val isPushEnabled: Boolean
) : BuildCacheService {

    @Volatile
    private var cachedConfig: TuistCacheConfiguration? = null

    private val configLock = Any()

    override fun load(key: BuildCacheKey, reader: BuildCacheEntryReader): Boolean {
        val config = getOrRefreshConfig() ?: return false
        val url = buildCacheUrl(config, key.hashCode)

        return executeWithRetry { currentConfig ->
            val connection = openConnection(url, currentConfig)
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

        val config = getOrRefreshConfig() ?: return
        val url = buildCacheUrl(config, key.hashCode)

        executeWithRetry<Unit> { currentConfig ->
            val connection = openConnection(url, currentConfig)
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

    private fun <T> executeWithRetry(operation: (TuistCacheConfiguration) -> T): T {
        val config = getOrRefreshConfig()
            ?: throw BuildCacheException("Failed to get Tuist cache configuration")

        return try {
            operation(config)
        } catch (e: TokenExpiredException) {
            // Token expired, refresh and retry once
            // Use synchronized to ensure only one thread refreshes at a time
            val refreshedConfig = synchronized(configLock) {
                // Double-check: another thread might have already refreshed
                val currentConfig = cachedConfig
                if (currentConfig != null && currentConfig !== config) {
                    // Config was already refreshed by another thread, use it
                    currentConfig
                } else {
                    // We need to refresh
                    invalidateAndRefreshConfig()
                }
            } ?: throw BuildCacheException("Failed to refresh Tuist cache configuration")
            operation(refreshedConfig)
        }
    }

    private fun getOrRefreshConfig(): TuistCacheConfiguration? {
        // Fast path: return cached config if available
        cachedConfig?.let { return it }

        // Slow path: acquire lock and initialize
        synchronized(configLock) {
            // Double-check after acquiring lock
            cachedConfig?.let { return it }
            val newConfig = configurationProvider.getConfiguration()
            cachedConfig = newConfig
            return newConfig
        }
    }

    private fun invalidateAndRefreshConfig(): TuistCacheConfiguration? {
        // Must be called while holding configLock
        cachedConfig = null
        val newConfig = configurationProvider.getConfiguration()
        cachedConfig = newConfig
        return newConfig
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

    private fun openConnection(url: URI, config: TuistCacheConfiguration): HttpURLConnection {
        val connection = url.toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = 30_000
        connection.readTimeout = 60_000

        // Bearer token authentication
        connection.setRequestProperty("Authorization", "Bearer ${config.token}")

        return connection
    }

    private class TokenExpiredException : Exception()
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
