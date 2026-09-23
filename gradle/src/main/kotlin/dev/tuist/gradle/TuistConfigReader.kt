package dev.tuist.gradle

import dev.tuist.gradle.services.GetCacheEndpointsService
import okhttp3.OkHttpClient
import okhttp3.Request
import org.gradle.api.logging.Logging
import java.io.File
import java.io.InterruptedIOException
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

class CacheEndpointBeingPreparedException(accountHandle: String) : RuntimeException(
    "The remote cache for account '$accountHandle' is still being prepared. " +
        "This build uses the local cache, and the remote cache is used as soon as it is ready."
)

class CacheEndpointsUnreachableException(endpoints: List<String>) : RuntimeException(
    "None of the cache endpoints are reachable: ${endpoints.joinToString(", ")}. " +
        "Check your internet connection and firewall settings."
)

object CacheEndpointResolver {
    /**
     * How long resolution waits for a cache instance the server is preparing. An account's instance
     * is prepared on demand, typically in seconds, so waiting beats running the build without it.
     */
    private const val PROVISIONING_WAIT_MS = 30_000L
    private const val PROVISIONING_POLL_INTERVAL_MS = 250L

    private val logger = Logging.getLogger(CacheEndpointResolver::class.java)

    fun resolve(
        serverURL: URI,
        accountHandle: String,
        tokenProvider: TokenProvider,
        envProvider: (String) -> String? = { System.getenv(it) },
        httpClients: TuistHttpClients = TuistHttpClients(),
        getCacheEndpointsService: GetCacheEndpointsService = GetCacheEndpointsService(httpClients),
        provisioningWaitMs: Long = PROVISIONING_WAIT_MS,
        provisioningPollIntervalMs: Long = PROVISIONING_POLL_INTERVAL_MS,
        sleeper: (Long) -> Unit = { Thread.sleep(it) },
        nanoTime: () -> Long = System::nanoTime
    ): String {
        val envEndpoint = envProvider("TUIST_CACHE_ENDPOINT")
        if (!envEndpoint.isNullOrBlank()) {
            return envEndpoint
        }

        val fetch = { timeoutMs: Long? ->
            getCacheEndpointsService.getCacheEndpoints(
                serverURL = serverURL,
                accountHandle = accountHandle,
                tokenProvider = tokenProvider,
                timeoutMs = timeoutMs
            )
        }
        var resolution = fetch(null)
        val beingPrepared = { resolution.endpoints.isEmpty() && resolution.provisioning == true }
        if (beingPrepared() && provisioningWaitMs > 0 && provisioningPollIntervalMs > 0) {
            logger.lifecycle(
                "Tuist: The remote cache for account '$accountHandle' is being prepared. " +
                    "Waiting up to ${provisioningWaitMs / 1_000} seconds for it to be ready."
            )
            // Wall-clock budget from the first answer: requests count against it as much as the
            // pauses between them, and neither is allowed to run past it.
            val deadline = nanoTime() + TimeUnit.MILLISECONDS.toNanos(provisioningWaitMs)
            val remainingMs = { TimeUnit.NANOSECONDS.toMillis(deadline - nanoTime()) }
            while (beingPrepared()) {
                val untilDeadlineMs = remainingMs()
                if (untilDeadlineMs <= 0) break
                sleeper(minOf(provisioningPollIntervalMs, untilDeadlineMs))

                val budgetMs = remainingMs()
                if (budgetMs <= 0) break
                resolution = try {
                    fetch(budgetMs)
                } catch (_: InterruptedIOException) {
                    break
                }
            }
        }
        val endpoints = resolution.endpoints

        if (endpoints.isEmpty()) {
            if (resolution.provisioning == true) {
                throw CacheEndpointBeingPreparedException(accountHandle)
            }
            throw NoCacheEndpointsException(accountHandle)
        }

        return if (endpoints.size == 1) {
            endpoints[0]
        } else {
            // Stable managed URLs can coexist with custom/self-hosted caches. The API list is
            // unranked, so these and regional fallback responses still need client selection.
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
