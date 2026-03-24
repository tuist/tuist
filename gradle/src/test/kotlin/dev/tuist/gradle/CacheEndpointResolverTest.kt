package dev.tuist.gradle

import dev.tuist.gradle.services.GetCacheEndpointsService
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.Test
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


    private fun stubService(endpoints: List<String>): GetCacheEndpointsService {
        return object : GetCacheEndpointsService() {
            override fun getCacheEndpoints(
                serverURL: URI,
                accountHandle: String,
                tokenProvider: TokenProvider
            ): List<String> = endpoints
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

    @Test
    fun `multiple endpoints selects fastest by latency`() {
        val fastServer = MockWebServer()
        val slowServer = MockWebServer()
        fastServer.enqueue(MockResponse().setBody("ok"))
        // Use a large delay to ensure deterministic ordering despite thread scheduling variance
        slowServer.enqueue(MockResponse().setBody("ok").setBodyDelay(3, TimeUnit.SECONDS))
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
                tokenProvider: TokenProvider
            ): List<String> {
                callCount++
                return listOf("https://cache.dev")
            }
        }

        val envProvider: (String) -> String? = { null }

        CacheEndpointResolver.resolve(serverURL, accountHandle, stubTokenProvider, envProvider, countingService)
        CacheEndpointResolver.resolve(serverURL, accountHandle, stubTokenProvider, envProvider, countingService)

        assertEquals(2, callCount)
    }
}
