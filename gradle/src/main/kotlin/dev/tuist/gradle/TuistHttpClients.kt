package dev.tuist.gradle

import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.URI
import java.util.concurrent.TimeUnit

/**
 * Single source of truth for the HTTP machinery the Tuist Gradle plugin uses.
 *
 * Every HTTP-using service takes a [TuistHttpClients] instance and asks it for
 * the client it needs. Cross-cutting concerns (proxy, headers, retry, logging,
 * metrics, SSL) live in exactly one place, and the underlying OkHttp connection
 * pool is shared.
 *
 * When the `HTTPS_PROXY` or `HTTP_PROXY` environment variable is set, the
 * clients automatically route requests through it; otherwise they use direct
 * connections. No explicit configuration is exposed to users.
 */
open class TuistHttpClients(
    private val environmentVariables: Map<String, String> = System.getenv()
) {

    val javaProxy: java.net.Proxy? by lazy { environmentProxy() }

    open val okHttp: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(DEFAULT_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(DEFAULT_READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .addInterceptor(FeatureFlagsInterceptor(environmentVariables))
            .applyProxy()
            .build()
    }

    open val latencyClient: OkHttpClient by lazy {
        okHttp.newBuilder()
            .connectTimeout(LATENCY_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(LATENCY_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    open fun unauthenticatedRetrofit(serverURL: URI): Retrofit = Retrofit.Builder()
        .baseUrl(normalizeBaseUrl(serverURL))
        .client(okHttp)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    open fun authenticatedRetrofit(serverURL: URI, tokenProvider: TokenProvider): Retrofit {
        val client = okHttp.newBuilder()
            .addInterceptor(AuthInterceptor(tokenProvider))
            .build()
        return Retrofit.Builder()
            .baseUrl(normalizeBaseUrl(serverURL))
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    open fun openConnection(
        url: URI,
        connectTimeoutMs: Int = DEFAULT_CONNECT_TIMEOUT_MS,
        readTimeoutMs: Int = DEFAULT_READ_TIMEOUT_MS
    ): HttpURLConnection {
        val raw = javaProxy?.let { url.toURL().openConnection(it) } ?: url.toURL().openConnection()
        val connection = raw as HttpURLConnection
        connection.connectTimeout = connectTimeoutMs
        connection.readTimeout = readTimeoutMs
        FeatureFlagsHeaders.headerValue(environmentVariables)?.let { headerValue ->
            connection.setRequestProperty(FeatureFlagsHeaders.HEADER_NAME, headerValue)
        }
        return connection
    }

    private fun OkHttpClient.Builder.applyProxy(): OkHttpClient.Builder {
        javaProxy?.let { proxy(it) }
        return this
    }

    private fun normalizeBaseUrl(serverURL: URI): String {
        val base = serverURL.resolve("/")
        return base.toASCIIString()
    }

    companion object {
        private const val DEFAULT_CONNECT_TIMEOUT_SECONDS = 30L
        private const val DEFAULT_READ_TIMEOUT_SECONDS = 60L
        private const val LATENCY_TIMEOUT_SECONDS = 5L
        private const val DEFAULT_CONNECT_TIMEOUT_MS = 30_000
        private const val DEFAULT_READ_TIMEOUT_MS = 60_000

        private val PROXY_ENV_VARS = listOf("HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy")

        private fun environmentProxy(): java.net.Proxy? {
            for (name in PROXY_ENV_VARS) {
                val value = System.getenv(name)
                if (!value.isNullOrBlank()) {
                    val uri = runCatching { URI(value) }.getOrNull() ?: continue
                    val host = uri.host ?: continue
                    val port = if (uri.port != -1) uri.port else defaultProxyPort(uri.scheme)
                    return java.net.Proxy(java.net.Proxy.Type.HTTP, InetSocketAddress(host, port))
                }
            }
            return null
        }

        private fun defaultProxyPort(scheme: String?): Int = when (scheme?.lowercase()) {
            "https" -> 443
            "http" -> 80
            else -> 8080
        }
    }
}
