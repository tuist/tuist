package dev.tuist.gradle

import dev.tuist.gradle.api.model.CacheEndpoints
import dev.tuist.gradle.services.GetCacheEndpointsService
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.Test
import java.io.InterruptedIOException
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CacheEndpointResolverTest {

    private val serverURL = URI.create("https://tuist.dev")
    private val accountHandle = "my-org"

    private val stubTokenProvider = object : TokenProvider(URI.create("https://tuist.dev"),
        envProvider = { "stub-token" },
        tokenCacheFactory = { CachedValueStore() }) {}


    private fun stubService(endpoints: List<String>, provisioning: Boolean? = null): GetCacheEndpointsService {
        return object : GetCacheEndpointsService() {
            override fun getCacheEndpoints(
                serverURL: URI,
                accountHandle: String,
                tokenProvider: TokenProvider,
                timeoutMs: Long?
            ): CacheEndpoints = CacheEndpoints(endpoints = endpoints, provisioning = provisioning)
        }
    }

    @Test
    fun `env var TUIST_CACHE_ENDPOINT returns immediately`() {
        val result = CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = { if (it == "TUIST_CACHE_ENDPOINT") "https://env-cache.dev" else null },
            getCacheEndpointsService = stubService(emptyList())
        )
        assertEquals("https://env-cache.dev", result)
    }

    @Test
    fun `single endpoint from API is used directly`() {
        val result = CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = { null },
            getCacheEndpointsService = stubService(listOf("https://cache1.dev"))
        )
        assertEquals("https://cache1.dev", result)
    }

    @Test
    fun `no endpoints throws NoCacheEndpointsException`() {
        assertFailsWith<NoCacheEndpointsException> {
            CacheEndpointResolver.resolve(
                serverURL, accountHandle, stubTokenProvider,
                envProvider = { null },
                getCacheEndpointsService = stubService(emptyList())
            )
        }
    }

    /** A server whose answers take [responseMs] of simulated time, honoring the call timeout. */
    private class SlowService(
        private val clock: FakeClock,
        private val responseMs: Long,
        private val readyAfterCalls: Int = Int.MAX_VALUE
    ) : GetCacheEndpointsService() {
        var calls = 0

        override fun getCacheEndpoints(
            serverURL: URI,
            accountHandle: String,
            tokenProvider: TokenProvider,
            timeoutMs: Long?
        ): CacheEndpoints {
            if (timeoutMs != null && responseMs > timeoutMs) {
                clock.advance(timeoutMs)
                throw InterruptedIOException("timeout")
            }
            clock.advance(responseMs)
            calls++
            return if (calls >= readyAfterCalls) {
                CacheEndpoints(endpoints = listOf("https://acme-us-east-1.kura.tuist.dev"), provisioning = false)
            } else {
                CacheEndpoints(endpoints = emptyList(), provisioning = true)
            }
        }
    }

    private class FakeClock {
        var nanos = 0L
        fun advance(ms: Long) {
            nanos += TimeUnit.MILLISECONDS.toNanos(ms)
        }
        val elapsedMs get() = TimeUnit.NANOSECONDS.toMillis(nanos)
    }

    @Test
    fun `waits for an endpoint the server is preparing`() {
        val clock = FakeClock()
        val service = SlowService(clock, responseMs = 0, readyAfterCalls = 3)

        val result = CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = { null },
            getCacheEndpointsService = service,
            sleeper = clock::advance,
            nanoTime = { clock.nanos }
        )

        assertEquals("https://acme-us-east-1.kura.tuist.dev", result)
        assertEquals(3, service.calls)
    }

    @Test
    fun `asks again for an endpoint being prepared within a fraction of a second`() {
        // An instance being prepared typically serves within seconds, so a whole second
        // between requests would be a large share of the wait.
        val clock = FakeClock()
        val service = SlowService(clock, responseMs = 0, readyAfterCalls = 3)
        val pauses = mutableListOf<Long>()

        CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = { null },
            getCacheEndpointsService = service,
            sleeper = { pauses += it; clock.advance(it) },
            nanoTime = { clock.nanos }
        )

        assertEquals(listOf(250L, 250L), pauses)
    }

    @Test
    fun `counts the time requests take against the wait`() {
        // Every answer takes 500ms. Counting only the pauses, a 3s wait polled every second
        // would make three more requests and run for 4.5s after the first answer.
        val clock = FakeClock()
        val service = SlowService(clock, responseMs = 500)

        assertFailsWith<CacheEndpointBeingPreparedException> {
            CacheEndpointResolver.resolve(
                serverURL, accountHandle, stubTokenProvider,
                envProvider = { null },
                getCacheEndpointsService = service,
                provisioningWaitMs = 3_000,
                provisioningPollIntervalMs = 1_000,
                sleeper = clock::advance,
                nanoTime = { clock.nanos }
            )
        }
        assertEquals(3, service.calls)
        assertEquals(3_500, clock.elapsedMs)
    }

    @Test
    fun `does not let a request outlast the wait`() {
        // Every answer takes 2.5s. The first one starts the 3s wait; after a 1s pause only 2s
        // remain, so the next request is cut off when the wait ends.
        val clock = FakeClock()
        val service = SlowService(clock, responseMs = 2_500)

        assertFailsWith<CacheEndpointBeingPreparedException> {
            CacheEndpointResolver.resolve(
                serverURL, accountHandle, stubTokenProvider,
                envProvider = { null },
                getCacheEndpointsService = service,
                provisioningWaitMs = 3_000,
                provisioningPollIntervalMs = 1_000,
                sleeper = clock::advance,
                nanoTime = { clock.nanos }
            )
        }
        assertEquals(5_500, clock.elapsedMs)
    }

    @Test
    fun `does not wait when the server is not preparing an endpoint`() {
        var sleeps = 0
        assertFailsWith<NoCacheEndpointsException> {
            CacheEndpointResolver.resolve(
                serverURL, accountHandle, stubTokenProvider,
                envProvider = { null },
                getCacheEndpointsService = stubService(emptyList(), provisioning = false),
                sleeper = { sleeps++ }
            )
        }
        assertEquals(0, sleeps)
    }

    @Test
    fun `multiple endpoints selects fastest by latency`() {
        val fastServer = MockWebServer()
        val slowServer = MockWebServer()
        fastServer.enqueue(MockResponse().setBody("ok"))
        // measureLatency times how long execute() takes, which returns as soon as
        // response headers arrive — setBodyDelay only delays the body and leaves
        // headers instant, so we delay headers to make the ordering deterministic.
        slowServer.enqueue(MockResponse().setBody("ok").setHeadersDelay(3, TimeUnit.SECONDS))
        fastServer.start()
        slowServer.start()

        try {
            val fastUrl = fastServer.url("/").toString().trimEnd('/')
            val slowUrl = slowServer.url("/").toString().trimEnd('/')

            val result = CacheEndpointResolver.resolve(
                serverURL, accountHandle, stubTokenProvider,
                envProvider = { null },
                getCacheEndpointsService = stubService(listOf(slowUrl, fastUrl))
            )

            assertEquals(fastUrl, result)
        } finally {
            fastServer.shutdown()
            slowServer.shutdown()
        }
    }

    @Test
    fun `each call invokes the service (no static caching)`() {
        var callCount = 0
        val countingService = object : GetCacheEndpointsService() {
            override fun getCacheEndpoints(
                serverURL: URI,
                accountHandle: String,
                tokenProvider: TokenProvider,
                timeoutMs: Long?
            ): CacheEndpoints {
                callCount++
                return CacheEndpoints(endpoints = listOf("https://cache.dev"))
            }
        }

        val envProvider: (String) -> String? = { null }

        CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = envProvider,
            getCacheEndpointsService = countingService
        )
        CacheEndpointResolver.resolve(
            serverURL, accountHandle, stubTokenProvider,
            envProvider = envProvider,
            getCacheEndpointsService = countingService
        )

        assertEquals(2, callCount)
    }
}
