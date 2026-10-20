package dev.tuist.gradle

import java.net.HttpURLConnection
import java.net.URI

class TokenExpiredException : Exception("Tuist auth token expired; retrying with a refreshed token")
class ReportAuthenticationRequiredException : Exception("The Tuist server requires authentication for this report; check the self-hosted publishing policy.")

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
        if (config.token.isNotEmpty()) connection.setRequestProperty("Authorization", "Bearer ${config.token}")
        return connection
    }

    fun <T> execute(operation: (CacheConfiguration) -> T): T {
        val config = getOrFetchConfig()

        return try {
            operation(config)
        } catch (e: TokenExpiredException) {
            if (config.token.isEmpty()) throw ReportAuthenticationRequiredException()
            val refreshedConfig = synchronized(configLock) {
                val currentConfig = cachedConfig
                if (currentConfig != null && currentConfig !== config) {
                    currentConfig
                } else {
                    val newConfig = configurationProvider.getConfiguration(forceRefresh = true)
                    if (newConfig.token.isBlank()) throw e
                    cachedConfig = newConfig
                    newConfig
                }
            }
            if (refreshedConfig.token.isBlank()) throw e
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
