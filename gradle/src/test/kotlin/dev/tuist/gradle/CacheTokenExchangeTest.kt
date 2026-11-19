package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.gradle.caching.BuildCacheException
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class CacheTokenExchangeTest {
    @TempDir lateinit var directory: File

    private fun provider(url: String) = DefaultConfigurationProvider(
        project = "acme/widgets", serverUrl = url, projectDir = directory,
        httpClients = TuistHttpClients(useEnvironmentProxy = false, retryPolicy = RetryPolicy(sleeper = {})),
        tokenProviderFactory = { uri ->
            TokenProvider(uri, credentialStore = CredentialStore(File(directory, "credentials")),
                envProvider = { key -> when (key) {
                    "TUIST_TOKEN" -> "ci-token"
                    else -> null
                } },
                tokenCacheFactory = { CachedValueStore() })
        }
    )

    private fun MockWebServer.enqueueEndpoint() =
        enqueue(MockResponse().setBody("""{"endpoints":["https://cache.example"]}"""))

    @Test fun `cache requests send the exchanged cache token and reuse it`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueueEndpoint()
            server.enqueue(MockResponse().setBody("""{"token":"cache-token","expires_in":1800}"""))
            val provider = provider(server.url("/").toString())

            assertEquals("cache-token", provider.getConfiguration().token)
            assertEquals("cache-token", provider.getConfiguration().token)

            assertEquals("/api/cache/endpoints?account_handle=acme", server.takeRequest().path)
            val request = server.takeRequest()
            assertEquals("POST", request.method)
            assertEquals("/api/cache/token?full_handle=acme%2Fwidgets", request.path)
            assertEquals("Bearer ci-token", request.getHeader("Authorization"))
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun `a server that cannot mint a cache token leaves the credential in use`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueueEndpoint()
            server.enqueue(MockResponse().setResponseCode(404))
            val provider = provider(server.url("/").toString())

            assertEquals("ci-token", provider.getConfiguration().token)
            assertEquals("ci-token", provider.getConfiguration().token)
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun `an exhausted plan refuses the cache instead of sending the credential`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueueEndpoint()
            server.enqueue(MockResponse().setResponseCode(402).setBody("""{"message":"The plan is used up."}"""))

            val error = assertFailsWith<BuildCacheException> { provider(server.url("/").toString()).getConfiguration() }
            assertEquals("The plan is used up.", error.message)
        }
    }
}
