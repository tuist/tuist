package dev.tuist.gradle

import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.TimeUnit

/**
 * Single source of truth for the HTTP machinery the Tuist Gradle plugin uses.
 *
 * Instead of threading [Proxy] through every class that happens to make an HTTP
 * request, each HTTP-using service takes a [TuistHttpClients] instance and asks
 * it for the client it needs. That way proxy configuration (and any future
 * cross-cutting concern — headers, retry, logging, metrics, SSL) lives in
 * exactly one place, and the underlying OkHttp connection pool is shared.
 */
open class TuistHttpClients(val proxy: Proxy = Proxy.None) {

    /**
     * The resolved `java.net.Proxy` for this configuration, or `null` when no
     * proxy applies. Exposed for call sites that bypass OkHttp (e.g.
     * `HttpURLConnection.openConnection(Proxy)`).
     */
    val javaProxy: java.net.Proxy? by lazy { proxy.resolve() }

    /**
     * The shared [OkHttpClient] every OkHttp-based caller should reuse. OkHttp
     * recommends sharing a single instance across the whole app so connection
     * pools, thread pools, and response caches can be reused.
     */
    open val okHttp: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(DEFAULT_CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(DEFAULT_READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .applyProxy()
            .build()
    }

    /**
     * A short-timeout variant of [okHttp], used by [CacheEndpointResolver] to
     * probe latency across candidate cache endpoints without holding the build
     * for the full 30-second timeout.
     */
    open val latencyClient: OkHttpClient by lazy {
        okHttp.newBuilder()
            .connectTimeout(LATENCY_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(LATENCY_TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }

    /**
     * Retrofit client for unauthenticated calls against a Tuist server.
     */
    open fun unauthenticatedRetrofit(serverURL: URI): Retrofit = Retrofit.Builder()
        .baseUrl(normalizeBaseUrl(serverURL))
        .client(okHttp)
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    /**
     * Retrofit client that injects a bearer token on every request via the
     * given [tokenProvider]. The underlying OkHttp client is branched from
     * [okHttp] so the connection pool is shared.
     */
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

    /**
     * Opens an [HttpURLConnection] against the given URL, routing through the
     * configured proxy when one is set. Callers are responsible for applying
     * request headers and calling [HttpURLConnection.disconnect].
     */
    open fun openConnection(
        url: URI,
        connectTimeoutMs: Int = DEFAULT_CONNECT_TIMEOUT_MS,
        readTimeoutMs: Int = DEFAULT_READ_TIMEOUT_MS
    ): HttpURLConnection {
        val raw = javaProxy?.let { url.toURL().openConnection(it) } ?: url.toURL().openConnection()
        val connection = raw as HttpURLConnection
        connection.connectTimeout = connectTimeoutMs
        connection.readTimeout = readTimeoutMs
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
        /** Convenience factory used by call sites that don't need a proxy. */
        val NONE: TuistHttpClients = TuistHttpClients(Proxy.None)

        private const val DEFAULT_CONNECT_TIMEOUT_SECONDS = 30L
        private const val DEFAULT_READ_TIMEOUT_SECONDS = 60L
        private const val LATENCY_TIMEOUT_SECONDS = 5L
        private const val DEFAULT_CONNECT_TIMEOUT_MS = 30_000
        private const val DEFAULT_READ_TIMEOUT_MS = 60_000
    }
}
