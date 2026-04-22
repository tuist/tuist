package dev.tuist.gradle

import dev.tuist.gradle.services.GetCacheEndpointsService
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

object ServerUrlResolver {
    private const val DEFAULT_URL = "https://tuist.dev"

    fun resolve(extensionUrl: String?, projectDir: File?): String {
        val envUrl = System.getenv("TUIST_URL")
        if (!envUrl.isNullOrBlank()) return envUrl

        if (!extensionUrl.isNullOrBlank() && extensionUrl != DEFAULT_URL) {
            return extensionUrl
        }

        if (projectDir != null) {
            findTomlFile(projectDir)?.let { tomlFile ->
                TomlParser.parse(tomlFile)?.url?.takeIf { it.isNotBlank() }?.let { return it }
            }
        }

        return extensionUrl ?: DEFAULT_URL
    }

    internal fun findTomlFile(startDir: File): File? {
        var dir: File? = startDir
        while (dir != null) {
            val toml = File(dir, "tuist.toml")
            if (toml.exists()) return toml
            dir = dir.parentFile
        }
        return null
    }
}

class NoCacheEndpointsException(accountHandle: String) : RuntimeException(
    "No cache endpoints available for account '$accountHandle'. " +
        "Verify your project is correctly configured at https://tuist.dev."
)

class CacheEndpointsUnreachableException(endpoints: List<String>) : RuntimeException(
    "None of the cache endpoints are reachable: ${endpoints.joinToString(", ")}. " +
        "Check your internet connection and firewall settings."
)

object CacheEndpointResolver {

    fun resolve(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider,
        envProvider: (String) -> String? = { System.getenv(it) },
        httpClients: TuistHttpClients = TuistHttpClients(),
        getCacheEndpointsService: GetCacheEndpointsService = GetCacheEndpointsService(httpClients)
    ): String {
        val envEndpoint = envProvider("TUIST_CACHE_ENDPOINT")
        if (!envEndpoint.isNullOrBlank()) {
            return envEndpoint
        }

        val cacheTechnology = CacheTechnology.fromEnvironment(envProvider)
        val endpoints = getCacheEndpointsService.getCacheEndpoints(
            serverURL = serverURL,
            accountHandle = accountHandle,
            tokenProvider = tokenProvider,
            cacheTechnology = cacheTechnology
        )

        if (endpoints.isEmpty()) {
            throw NoCacheEndpointsException(accountHandle)
        }

        return if (endpoints.size == 1) {
            endpoints[0]
        } else {
            pickFastestEndpoint(endpoints, httpClients)
                ?: throw CacheEndpointsUnreachableException(endpoints)
        }
    }

    internal fun pickFastestEndpoint(
        endpoints: List<String>,
        httpClients: TuistHttpClients = TuistHttpClients()
    ): String? {
        val bestEndpoint = AtomicReference<String?>(null)
        val bestLatency = AtomicReference(Long.MAX_VALUE)
        val latch = CountDownLatch(endpoints.size)

        val latencyClient = httpClients.latencyClient

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
                    // skip unreachable endpoint
                } finally {
                    latch.countDown()
                }
            }.start()
        }

        latch.await(10, TimeUnit.SECONDS)
        return bestEndpoint.get()
    }

    internal fun measureLatency(endpointUrl: String, client: OkHttpClient): Long {
        val baseUri = URI.create(endpointUrl)
        val upUri = baseUri.resolve(baseUri.path.trimEnd('/') + "/up")
        val request = Request.Builder()
            .url(upUri.toURL())
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
}
