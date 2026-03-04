package dev.tuist.gradle

import dev.tuist.gradle.services.GetCacheEndpointsService
import okhttp3.OkHttpClient
import okhttp3.Request
import org.gradle.api.logging.Logging
import java.io.File
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

data class TomlConfig(val project: String?, val url: String?)

object TomlParser {
    fun parse(file: File): TomlConfig? {
        if (!file.exists()) return null
        return try {
            val content = file.readText()
            TomlConfig(
                project = extractStringValue(content, "project"),
                url = extractStringValue(content, "url")
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun extractStringValue(content: String, key: String): String? {
        val regex = Regex("""^\s*$key\s*=\s*"([^"]*)"\s*$""", RegexOption.MULTILINE)
        return regex.find(content)?.groupValues?.get(1)
    }
}

object ServerUrlResolver {
    private const val DEFAULT_URL = "https://tuist.dev"

    fun resolve(extensionUrl: String?, projectDir: File?): String {
        if (!extensionUrl.isNullOrBlank() && extensionUrl != DEFAULT_URL) {
            return extensionUrl
        }

        val envUrl = System.getenv("TUIST_URL")
        if (!envUrl.isNullOrBlank()) return envUrl

        if (projectDir != null) {
            val tomlConfig = TomlParser.parse(File(projectDir, "tuist.toml"))
            if (!tomlConfig?.url.isNullOrBlank()) return tomlConfig!!.url!!
        }

        return extensionUrl ?: DEFAULT_URL
    }
}

object CacheEndpointResolver {
    private val logger = Logging.getLogger(CacheEndpointResolver::class.java)

    @Volatile
    private var cachedEndpoint: String? = null

    fun resolve(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider
    ): String {
        cachedEndpoint?.let { return it }

        val envEndpoint = System.getenv("TUIST_CACHE_ENDPOINT")
        if (!envEndpoint.isNullOrBlank()) {
            cachedEndpoint = envEndpoint
            return envEndpoint
        }

        val endpoints = try {
            GetCacheEndpointsService().getCacheEndpoints(serverURL, accountHandle, tokenProvider)
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to fetch cache endpoints: ${e.message}")
            null
        }

        val result = when {
            endpoints.isNullOrEmpty() -> serverURL.toString()
            endpoints.size == 1 -> endpoints[0]
            else -> pickFastestEndpoint(endpoints) ?: endpoints[0]
        }

        cachedEndpoint = result
        return result
    }

    private fun pickFastestEndpoint(endpoints: List<String>): String? {
        val bestEndpoint = AtomicReference<String?>(null)
        val bestLatency = AtomicReference(Long.MAX_VALUE)
        val latch = CountDownLatch(endpoints.size)

        val latencyClient = OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()

        for (endpoint in endpoints) {
            Thread {
                try {
                    val latency = measureLatency(endpoint, latencyClient)
                    synchronized(bestLatency) {
                        if (latency < bestLatency.get()) {
                            bestLatency.set(latency)
                            bestEndpoint.set(endpoint)
                        }
                    }
                } catch (_: Exception) {
                    // skip
                } finally {
                    latch.countDown()
                }
            }.start()
        }

        latch.await(10, TimeUnit.SECONDS)
        return bestEndpoint.get()
    }

    private fun measureLatency(endpointUrl: String, client: OkHttpClient): Long {
        val request = Request.Builder()
            .url("${endpointUrl.trimEnd('/')}/up")
            .get()
            .build()
        val start = System.nanoTime()
        return try {
            client.newCall(request).execute().use {
                TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            }
        } catch (_: Exception) {
            Long.MAX_VALUE
        }
    }

    internal fun resetCache() {
        cachedEndpoint = null
    }
}
