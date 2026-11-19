package dev.tuist.gradle

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.caching.BuildCacheException
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CacheTokenExchangeTest {
    @TempDir lateinit var directory: File

    private fun provider(url: String) = DefaultConfigurationProvider(
        project = "acme/widgets", serverUrl = url, projectDir = directory,
        httpClients = TuistHttpClients(useEnvironmentProxy = false, retryPolicy = RetryPolicy(sleeper = {})),
        tokenProviderFactory = { uri ->
            TokenProvider(uri, credentialStore = CredentialStore(File(directory, "credentials")),
                envProvider = { key -> if (key == "TUIST_TOKEN") "ci-token" else null },
                tokenCacheFactory = { CachedValueStore() })
        }
    )

    /**
     * Answers by path rather than in order: endpoint discovery is skipped when the environment
     * running the tests sets TUIST_CACHE_ENDPOINT, as CI does.
     */
    private fun MockWebServer.serve(exchange: MockResponse): MutableList<RecordedRequest> {
        val exchanges = CopyOnWriteArrayList<RecordedRequest>()
        dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path!!.startsWith("/api/cache/token") -> exchange.also { exchanges.add(request) }
                request.path!!.startsWith("/api/cache/endpoints") ->
                    MockResponse().setBody("""{"endpoints":["https://cache.example"]}""")
                else -> MockResponse().setResponseCode(404)
            }
        }
        return exchanges
    }

    @Test fun `cache requests send the exchanged cache token and reuse it`() {
        MockWebServer().use { server ->
            val exchanges = server.serve(MockResponse().setBody("""{"token":"cache-token","expires_in":1800}"""))
            server.start()
            val provider = provider(server.url("/").toString())

            assertEquals("cache-token", provider.getConfiguration().token)
            assertEquals("cache-token", provider.getConfiguration().token)

            assertEquals(1, exchanges.size)
            assertEquals("POST", exchanges[0].method)
            assertEquals("/api/cache/token?full_handle=acme%2Fwidgets", exchanges[0].path)
            assertEquals("Bearer ci-token", exchanges[0].getHeader("Authorization"))
        }
    }

    @Test fun `a cache that refuses the cache token gets the credential for the rest of the build`() {
        MockWebServer().use { server ->
            val exchanges = server.serve(MockResponse().setBody("""{"token":"cache-token","expires_in":1800}"""))
            server.start()
            val provider = provider(server.url("/").toString())

            assertEquals("cache-token", provider.getConfiguration().token)
            assertEquals("ci-token", provider.getConfiguration(forceRefresh = true).token)
            assertEquals("ci-token", provider.getConfiguration().token)
            assertEquals(1, exchanges.size)
        }
    }

    @Test fun `a server that cannot mint a cache token leaves the credential in use`() {
        MockWebServer().use { server ->
            val exchanges = server.serve(MockResponse().setResponseCode(404))
            server.start()
            val provider = provider(server.url("/").toString())

            assertEquals("ci-token", provider.getConfiguration().token)
            assertEquals("ci-token", provider.getConfiguration().token)
            assertEquals(1, exchanges.size)
        }
    }

    @Test fun `an exhausted plan refuses the cache instead of sending the credential`() {
        MockWebServer().use { server ->
            server.serve(MockResponse().setResponseCode(402).setBody("""{"message":"The plan is used up."}"""))
            server.start()

            val error = assertFailsWith<BuildCacheException> { provider(server.url("/").toString()).getConfiguration() }
            assertEquals("The plan is used up.", error.message)
        }
    }
}
