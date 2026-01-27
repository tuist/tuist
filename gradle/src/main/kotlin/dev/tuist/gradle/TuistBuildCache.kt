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
 * Build cache configuration type for Tuist.
 */
open class TuistBuildCache : AbstractBuildCache() {
    var fullHandle: String = ""
    var executablePath: String? = null
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

        val resolvedExecutablePath = configuration.executablePath ?: findTuistInPath()
            ?: throw BuildCacheException("Could not find 'tuist' executable. Please install Tuist or set executablePath in the tuist extension.")

        return TuistBuildCacheService(
            fullHandle = configuration.fullHandle,
            executablePath = resolvedExecutablePath,
            isPushEnabled = configuration.isPush,
            allowInsecureProtocol = configuration.allowInsecureProtocol
        )
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
}

/**
 * Custom BuildCacheService that handles authentication and automatic token refresh.
 *
 * When a 401 Unauthorized response is received, this service automatically
 * re-runs `tuist cache config` to refresh the token and retries the request.
 */
class TuistBuildCacheService(
    private val fullHandle: String,
    private val executablePath: String,
    private val isPushEnabled: Boolean,
    private val allowInsecureProtocol: Boolean
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
            val refreshedConfig = refreshConfig()
                ?: throw BuildCacheException("Failed to refresh Tuist cache configuration")
            operation(refreshedConfig)
        }
    }

    private fun getOrRefreshConfig(): TuistCacheConfiguration? {
        cachedConfig?.let { return it }

        synchronized(configLock) {
            cachedConfig?.let { return it }
            return refreshConfig()
        }
    }

    private fun refreshConfig(): TuistCacheConfiguration? {
        synchronized(configLock) {
            val newConfig = executeTuistCommand()
            cachedConfig = newConfig
            return newConfig
        }
    }

    private fun executeTuistCommand(): TuistCacheConfiguration? {
        val command = listOf(executablePath, "cache", "config", fullHandle, "--json")

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

    private fun buildCacheUrl(config: TuistCacheConfiguration, cacheKey: String): URI {
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

        // Basic authentication
        val credentials = "tuist:${config.token}"
        val encodedCredentials = java.util.Base64.getEncoder().encodeToString(credentials.toByteArray())
        connection.setRequestProperty("Authorization", "Basic $encodedCredentials")

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
    val accountHandle: String,
    val projectHandle: String
)
