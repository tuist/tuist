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

/**
 * Build cache configuration type for Tuist.
 */
open class TuistBuildCache : AbstractBuildCache() {
    var project: String? = null

    @Deprecated("No longer used. The plugin resolves auth natively.")
    var executablePath: String? = null
    var url: String? = null
    var allowInsecureProtocol: Boolean = false
    var proxy: Proxy = Proxy.None
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
            .config("project", configuration.project ?: "(from tuist.toml)")

        val httpClients = TuistHttpClients(configuration.proxy)
        val configurationProvider = DefaultConfigurationProvider(
            project = configuration.project,
            serverUrl = configuration.url ?: "https://tuist.dev",
            projectDir = java.io.File(System.getProperty("user.dir")),
            httpClients = httpClients
        )

        val httpClient = TuistHttpClient(configurationProvider, httpClients = httpClients)

        return TuistBuildCacheService(
            httpClient = httpClient,
            isPushEnabled = configuration.isPush
        )
    }
}

/**
 * Provides cache configuration including auth token and endpoint.
 */
interface ConfigurationProvider {
    fun getConfiguration(forceRefresh: Boolean = false): CacheConfiguration
}

data class ProjectHandle(val accountHandle: String, val projectHandle: String) {
    companion object {
        fun parse(fullName: String): ProjectHandle {
            val parts = fullName.split("/", limit = 2)
            return ProjectHandle(
                accountHandle = parts[0],
                projectHandle = parts.getOrElse(1) { "" }
            )
        }
    }
}

/**
 * Default configuration provider that resolves auth and cache endpoints natively.
 */
class DefaultConfigurationProvider(
    private val project: String?,
    private val serverUrl: String,
    private val projectDir: java.io.File,
    private val httpClients: TuistHttpClients = TuistHttpClients.NONE
) : ConfigurationProvider {

    private val resolvedServerUrl: java.net.URI by lazy {
        java.net.URI.create(ServerUrlResolver.resolve(extensionUrl = serverUrl, projectDir = projectDir))
    }

    private val resolvedProject: ProjectHandle by lazy {
        val fullName = if (!project.isNullOrBlank()) project
        else {
            val tomlFile = ServerUrlResolver.findTomlFile(projectDir)
            val toml = tomlFile?.let { TomlParser.parse(it) }
            toml?.project ?: throw RuntimeException(
                "No project configured. Set tuist { project = \"account/project\" } or create a tuist.toml with project = \"account/project\"."
            )
        }
        ProjectHandle.parse(fullName)
    }

    private val tokenProvider: TokenProvider by lazy {
        TokenProvider(resolvedServerUrl, httpClients = httpClients)
    }

    private val cacheEndpointCache: CachedValueStore<String> = CachedValueStore()

    override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration {
        val token = tokenProvider.getToken(forceRefresh)
        val handle = resolvedProject

        val cacheEndpoint = cacheEndpointCache.getValue(forceRefresh) {
            resolveCacheEndpoint(handle.accountHandle)
        }

        return CacheConfiguration(
            url = cacheEndpoint,
            token = token,
            accountHandle = handle.accountHandle,
            projectHandle = handle.projectHandle
        )
    }

    private fun resolveCacheEndpoint(accountHandle: String): Pair<String, Long?> {
        val endpoint = CacheEndpointResolver.resolve(
            serverURL = resolvedServerUrl,
            accountHandle = accountHandle,
            tokenProvider = tokenProvider,
            httpClients = httpClients
        )
        val expiresAtMs = System.currentTimeMillis() + CACHE_ENDPOINT_TTL_MS
        return Pair(endpoint, expiresAtMs)
    }

    companion object {
        private const val CACHE_ENDPOINT_TTL_MS = 60 * 60 * 1000L // 1 hour
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

/**
 * Data class representing the cache configuration.
 */
data class CacheConfiguration(
    val url: String,
    val token: String,
    @com.google.gson.annotations.SerializedName("account_handle")
    val accountHandle: String,
    @com.google.gson.annotations.SerializedName("project_handle")
    val projectHandle: String
)
