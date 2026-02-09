package dev.tuist.gradle

import java.net.HttpURLConnection
import java.net.URI

class TokenExpiredException : Exception()

class TuistHttpClient(
    private val configurationProvider: ConfigurationProvider,
    private val connectTimeoutMs: Int = 30_000,
    private val readTimeoutMs: Int = 60_000
) {
    @Volatile
    private var cachedConfig: TuistCacheConfiguration? = null

    private val configLock = Any()

    fun getConfig(): TuistCacheConfiguration? {
        cachedConfig?.let { return it }

        synchronized(configLock) {
            cachedConfig?.let { return it }
            val newConfig = configurationProvider.getConfiguration()
            cachedConfig = newConfig
            return newConfig
        }
    }

    fun openConnection(url: URI, config: TuistCacheConfiguration): HttpURLConnection {
        val connection = url.toURL().openConnection() as HttpURLConnection
        connection.connectTimeout = connectTimeoutMs
        connection.readTimeout = readTimeoutMs
        connection.setRequestProperty("Authorization", "Bearer ${config.token}")
        return connection
    }

    fun <T> execute(operation: (TuistCacheConfiguration) -> T): T {
        val config = getConfig()
            ?: throw IllegalStateException("Failed to get Tuist configuration")

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
            } ?: throw IllegalStateException("Failed to refresh Tuist configuration")
            operation(refreshedConfig)
        }
    }
}
