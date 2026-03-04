package dev.tuist.gradle

import org.gradle.caching.BuildCacheEntryReader
import org.gradle.caching.BuildCacheEntryWriter
import org.gradle.caching.BuildCacheException
import org.gradle.caching.BuildCacheKey
import org.gradle.caching.BuildCacheService
import org.gradle.caching.BuildCacheServiceFactory
import org.gradle.caching.configuration.AbstractBuildCache
import java.net.HttpURLConnection
import java.net.URI

open class TuistBuildCache : AbstractBuildCache() {
    var project: String? = null

    @Deprecated("No longer used. The plugin resolves auth natively.")
    var executablePath: String? = null
    var url: String? = null
    var allowInsecureProtocol: Boolean = false
}

class TuistBuildCacheServiceFactory : BuildCacheServiceFactory<TuistBuildCache> {

    override fun createBuildCacheService(
        configuration: TuistBuildCache,
        describer: BuildCacheServiceFactory.Describer
    ): BuildCacheService {
        describer
            .type("Tuist")
            .config("project", configuration.project ?: "(from tuist.toml)")

        val configurationProvider = DefaultConfigurationProvider(
            project = configuration.project,
            serverUrl = configuration.url ?: "https://tuist.dev",
            projectDir = java.io.File(System.getProperty("user.dir"))
        )

        val httpClient = TuistHttpClient(configurationProvider)

        return TuistBuildCacheService(
            httpClient = httpClient,
            isPushEnabled = configuration.isPush
        )
    }
}

interface ConfigurationProvider {
    fun getConfiguration(forceRefresh: Boolean = false): CacheConfiguration
}

class DefaultConfigurationProvider(
    private val project: String?,
    private val serverUrl: String,
    private val projectDir: java.io.File
) : ConfigurationProvider {

    private val resolvedServerUrl: java.net.URI by lazy {
        java.net.URI.create(ServerUrlResolver.resolve(extensionUrl = serverUrl, projectDir = projectDir))
    }

    private val resolvedProject: String by lazy {
        if (!project.isNullOrBlank()) project
        else {
            val toml = TomlParser.parse(java.io.File(projectDir, "tuist.toml"))
            toml?.project ?: throw RuntimeException(
                "No project configured. Set tuist { project = \"account/project\" } or create a tuist.toml with project = \"account/project\"."
            )
        }
    }

    private val tokenProvider: TokenProvider by lazy {
        TokenProvider(resolvedServerUrl)
    }

    @Volatile
    private var cachedCacheEndpoint: String? = null

    override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration {
        val token = tokenProvider.getToken(forceRefresh)
        val parts = resolvedProject.split("/", limit = 2)
        val accountHandle = parts[0]
        val projectHandle = parts.getOrElse(1) { "" }

        val cacheEndpoint = if (forceRefresh) {
            resolveCacheEndpoint(accountHandle)
        } else {
            cachedCacheEndpoint ?: resolveCacheEndpoint(accountHandle)
        }

        return CacheConfiguration(
            url = cacheEndpoint,
            token = token,
            accountHandle = accountHandle,
            projectHandle = projectHandle
        )
    }

    private fun resolveCacheEndpoint(accountHandle: String): String {
        val endpoint = try {
            CacheEndpointResolver.resolve(resolvedServerUrl, accountHandle, tokenProvider)
        } catch (_: Exception) {
            resolvedServerUrl.toString()
        }
        cachedCacheEndpoint = endpoint
        return endpoint
    }
}

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

    internal fun buildCacheUrl(config: CacheConfiguration, cacheKey: String): URI {
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

data class CacheConfiguration(
    val url: String,
    val token: String,
    @com.google.gson.annotations.SerializedName("account_handle")
    val accountHandle: String,
    @com.google.gson.annotations.SerializedName("project_handle")
    val projectHandle: String
)
