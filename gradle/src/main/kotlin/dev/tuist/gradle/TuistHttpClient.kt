package dev.tuist.gradle

import java.net.HttpURLConnection
import java.net.URI

class TokenExpiredException : Exception()

/**
 * High-level HTTP wrapper used by the cache and insights code paths: it owns
 * the configuration / token lifecycle and transparently retries once on 401.
 *
 * All actual transport is delegated to [TuistHttpClients], so the proxy and
 * any other cross-cutting HTTP concern only need to be configured in one place.
 */
class TuistHttpClient(
    private val configurationProvider: ConfigurationProvider,
    private val httpClients: TuistHttpClients = TuistHttpClients(),
    private val connectTimeoutMs: Int = 30_000,
    private val readTimeoutMs: Int = 60_000
) {
    @Volatile
    private var cachedConfig: CacheConfiguration? = null

    private val configLock = Any()

    fun openConnection(url: URI, config: CacheConfiguration): HttpURLConnection {
        val connection = httpClients.openConnection(url, connectTimeoutMs, readTimeoutMs)
        connection.setRequestProperty("Authorization", "Bearer ${config.token}")
        return connection
    }

    fun <T> execute(operation: (CacheConfiguration) -> T): T {
        val config = getOrFetchConfig()

        return try {
            operation(config)
        } catch (e: TokenExpiredException) {
            val refreshedConfig = synchronized(configLock) {
                val currentConfig = cachedConfig
                if (currentConfig != null && currentConfig !== config) {
                    currentConfig
                } else {
                    cachedConfig = null
                    val newConfig = configurationProvider.getConfiguration(forceRefresh = true)
                    cachedConfig = newConfig
                    newConfig
                }
            }
            operation(refreshedConfig)
        }
    }

    private fun getOrFetchConfig(): CacheConfiguration {
        cachedConfig?.let { return it }

        synchronized(configLock) {
            cachedConfig?.let { return it }
            val newConfig = configurationProvider.getConfiguration()
            cachedConfig = newConfig
            return newConfig
        }
    }
}
