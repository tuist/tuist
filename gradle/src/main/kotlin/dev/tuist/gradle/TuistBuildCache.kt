package dev.tuist.gradle

import org.gradle.caching.BuildCacheEntryReader
import org.gradle.caching.BuildCacheEntryWriter
import org.gradle.caching.BuildCacheException
import org.gradle.caching.BuildCacheKey
import org.gradle.caching.BuildCacheService
import org.gradle.caching.BuildCacheServiceFactory
import org.gradle.caching.configuration.AbstractBuildCache
import org.slf4j.LoggerFactory
import java.io.EOFException
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.util.HexFormat
import java.util.zip.ZipException

/**
 * Build cache configuration type for Tuist.
 */
open class TuistBuildCache : AbstractBuildCache() {
    var project: String? = null

    @Deprecated("No longer used. The plugin resolves auth natively.")
    var executablePath: String? = null
    var url: String? = null
    lateinit var projectDir: String
    var useEnvironmentProxy: Boolean = true
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
            .config("project", configuration.project ?: "(from tuist.toml)")

        val projectDir = java.io.File(configuration.projectDir)
        val httpClients = TuistHttpClients(useEnvironmentProxy = configuration.useEnvironmentProxy)
        val configurationProvider = DefaultConfigurationProvider(
            project = configuration.project,
            serverUrl = configuration.url ?: "https://tuist.dev",
            projectDir = projectDir,
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
    private val httpClients: TuistHttpClients = TuistHttpClients()
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
            val cacheKey = key.hashCode

            val connection = try {
                httpClient.openConnection(url, config).also { it.requestMethod = "GET" }
            } catch (e: Throwable) {
                throw cacheFailure("load", cacheKey, url, "Failed to open connection", cause = e)
            }

            val responseCode = try {
                connection.responseCode
            } catch (e: Throwable) {
                throw cacheFailure("load", cacheKey, url, "Failed to read HTTP response status", cause = e)
            }

            when (responseCode) {
                HttpURLConnection.HTTP_OK -> {
                    val expectedChecksum = parseChecksum(connection.getHeaderField(CHECKSUM_HEADER))
                    try {
                        connection.inputStream.use { input ->
                            reader.readFrom(expectedChecksum?.let { ChecksumVerifyingInputStream(input, it) } ?: input)
                        }
                        true
                    } catch (e: Throwable) {
                        val checksumMismatch = causalChain(e).filterIsInstance<ChecksumMismatchException>().firstOrNull()
                        if (checksumMismatch != null || looksLikeInvalidCompressedCacheEntry(e)) {
                            logCorruptCacheEntry(url, cacheKey, connection, checksumMismatch ?: e)
                            false
                        } else {
                            throw cacheFailure(
                                "load", cacheKey, url,
                                "Failed to read cache entry body (Content-Length=${connection.contentLengthLong})",
                                cause = e,
                                status = responseCode
                            )
                        }
                    }
                }
                HttpURLConnection.HTTP_NOT_FOUND -> false
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> throw cacheFailure(
                    "load", cacheKey, url,
                    "Server returned unexpected HTTP status",
                    status = responseCode,
                    body = readErrorBodySnippet(connection)
                )
            }
        }
    }

    override fun store(key: BuildCacheKey, writer: BuildCacheEntryWriter) {
        if (!isPushEnabled) return

        val checksumRefusal = storeOnce(key.hashCode, writer) ?: return
        logger.warn("Tuist: Retrying store because the server refused the cache entry body: {}", checksumRefusal.message)
        storeOnce(key.hashCode, writer)?.let { throw it }
    }

    /**
     * Returns the failure instead of throwing it when the server refuses the body's checksum (422).
     */
    private fun storeOnce(cacheKey: String, writer: BuildCacheEntryWriter): BuildCacheException? {
        val checksum = lazy { sha256Hex(writer) }

        return httpClient.execute { config ->
            val url = buildCacheUrl(config, cacheKey)

            val expectedChecksum = try {
                checksum.value
            } catch (e: Throwable) {
                throw cacheFailure("store", cacheKey, url, "Failed to compute cache entry checksum", cause = e)
            }

            val connection = try {
                httpClient.openConnection(url, config).also {
                    it.requestMethod = "PUT"
                    it.doOutput = true
                    it.setRequestProperty("Content-Type", "application/octet-stream")
                    it.setRequestProperty(CHECKSUM_HEADER, expectedChecksum)
                }
            } catch (e: Throwable) {
                throw cacheFailure("store", cacheKey, url, "Failed to open connection", cause = e)
            }

            try {
                connection.outputStream.use { output -> writer.writeTo(output) }
            } catch (e: Throwable) {
                throw cacheFailure(
                    "store", cacheKey, url,
                    "Failed to write cache entry body (size=${runCatching { writer.size }.getOrNull()})",
                    cause = e
                )
            }

            val responseCode = try {
                connection.responseCode
            } catch (e: Throwable) {
                throw cacheFailure("store", cacheKey, url, "Failed to read HTTP response status", cause = e)
            }

            when (responseCode) {
                HttpURLConnection.HTTP_OK, HttpURLConnection.HTTP_CREATED, HttpURLConnection.HTTP_NO_CONTENT -> null
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> {
                    val failure = cacheFailure(
                        "store", cacheKey, url,
                        "Server returned unexpected HTTP status",
                        status = responseCode,
                        body = readErrorBodySnippet(connection)
                    )
                    if (responseCode == HTTP_UNPROCESSABLE_ENTITY) failure else throw failure
                }
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

    companion object {
        internal const val CHECKSUM_HEADER = "tuist-checksum-sha256"
        private const val HTTP_UNPROCESSABLE_ENTITY = 422
        private const val ERROR_BODY_MAX_BYTES = 1024
        private val checksumPattern = Regex("[0-9a-fA-F]{64}")
        private val logger = LoggerFactory.getLogger(TuistBuildCacheService::class.java)
        private val invalidCompressionMessageHints = listOf(
            "unexpected end of zlib input stream",
            "not in gzip format",
            "invalid stored block lengths",
            "invalid distance too far back",
            "invalid entry compressed size",
            "end of central directory",
            "invalid code lengths set",
            "invalid literal/lengths set",
            "corrupt gzip trailer"
        )

        internal fun cacheFailure(
            operation: String,
            cacheKey: String,
            url: URI,
            description: String,
            cause: Throwable? = null,
            status: Int? = null,
            body: String? = null
        ): BuildCacheException {
            val message = buildString {
                append("Tuist ").append(operation).append(" failed for cache key ").append(cacheKey)
                if (status != null) append(" (HTTP ").append(status).append(')')
                append(": ").append(description)
                if (cause != null) {
                    val causeMessage = cause.message?.takeIf(String::isNotBlank) ?: "(no message)"
                    append(" — ").append(cause.javaClass.name).append(": ").append(causeMessage)
                }
                if (!body.isNullOrBlank()) {
                    append(" — response body: ").append(body)
                }
                append(" [host=").append(url.host ?: "<unknown>")
                append(", path=").append(url.rawPath).append(']')
            }
            return if (cause != null) BuildCacheException(message, cause) else BuildCacheException(message)
        }

        internal fun readErrorBodySnippet(connection: HttpURLConnection): String? {
            val stream: InputStream = try {
                connection.errorStream ?: return null
            } catch (_: Throwable) {
                return null
            }
            return try {
                stream.use { input ->
                    val bytes = input.readNBytes(ERROR_BODY_MAX_BYTES)
                    if (bytes.isEmpty()) null else String(bytes).trim().ifEmpty { null }
                }
            } catch (_: Throwable) {
                null
            }
        }

        internal fun looksLikeInvalidCompressedCacheEntry(error: Throwable): Boolean {
            return causalChain(error).any { candidate ->
                candidate is ZipException ||
                    candidate is EOFException ||
                    candidate.message
                        ?.lowercase()
                        ?.let { message -> invalidCompressionMessageHints.any(message::contains) }
                        ?: false
            }
        }

        private fun logCorruptCacheEntry(
            url: URI,
            cacheKey: String,
            connection: HttpURLConnection,
            error: Throwable
        ) {
            val rootCause = causalChain(error).last()
            logger.warn(
                "Tuist: Treating remote cache entry {} as a miss because it appears invalid while reading from {} " +
                    "(Content-Length={}, ETag={}, Last-Modified={}): {}: {}",
                cacheKey,
                "${url.host ?: "<unknown>"}${url.rawPath ?: ""}",
                connection.contentLengthLong,
                connection.getHeaderField("ETag") ?: "<none>",
                connection.getHeaderField("Last-Modified") ?: "<none>",
                rootCause.javaClass.name,
                rootCause.message ?: "(no message)"
            )
        }

        private fun causalChain(error: Throwable): Sequence<Throwable> =
            generateSequence(error) { current -> current.cause }

        // Hashing in its own pass keeps a single in-memory copy of the entry: HttpURLConnection
        // already buffers the request body. Gradle's writer copies from a packed file, so it can
        // be written more than once.
        private fun sha256Hex(writer: BuildCacheEntryWriter): String {
            val digest = MessageDigest.getInstance("SHA-256")
            DigestOutputStream(OutputStream.nullOutputStream(), digest).use { writer.writeTo(it) }
            return HexFormat.of().formatHex(digest.digest())
        }

        private fun parseChecksum(value: String?): String? =
            value?.trim()?.takeIf(checksumPattern::matches)?.lowercase()
    }
}

internal class ChecksumMismatchException(expected: String, actual: String) :
    IOException("Body does not match ${TuistBuildCacheService.CHECKSUM_HEADER}: declared $expected, received $actual")

/**
 * Hashes every byte read from [input]. The declared checksum covers the whole object, so it is
 * compared when [input] reports end of stream, which also catches a body that ends early.
 */
internal class ChecksumVerifyingInputStream(
    input: InputStream,
    private val expectedChecksum: String
) : FilterInputStream(input) {
    private val digest = MessageDigest.getInstance("SHA-256")
    private var actualChecksum: String? = null

    override fun read(): Int {
        val byte = super.read()
        if (byte == -1) verify() else digest.update(byte.toByte())
        return byte
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        val count = super.read(b, off, len)
        if (count == -1) verify() else digest.update(b, off, count)
        return count
    }

    override fun skip(n: Long): Long {
        if (n <= 0) return 0
        val count = read(ByteArray(minOf(n, 8192L).toInt()))
        return if (count == -1) 0 else count.toLong()
    }

    override fun markSupported(): Boolean = false

    private fun verify() {
        val actual = actualChecksum ?: HexFormat.of().formatHex(digest.digest()).also { actualChecksum = it }
        if (actual != expectedChecksum) throw ChecksumMismatchException(expectedChecksum, actual)
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
