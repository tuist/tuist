package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

class CacheAccessDiscoveryTest {
    @TempDir lateinit var directory: File

    private fun provider(url: String, token: String? = null, endpoint: String? = null) = DefaultConfigurationProvider(
        project = "acme/widgets", serverUrl = url, projectDir = directory,
        httpClients = TuistHttpClients(useEnvironmentProxy = false, retryPolicy = RetryPolicy(sleeper = {})),
        tokenProviderFactory = { uri ->
            TokenProvider(uri, credentialStore = CredentialStore(File(directory, "credentials")),
                envProvider = { key -> when (key) {
                    "TUIST_TOKEN" -> token
                    "TUIST_CACHE_ENDPOINT" -> endpoint
                    else -> null
                } },
                tokenCacheFactory = { CachedValueStore() })
        }
    )

    @Test fun `cache-only policy permits unsigned cache transfers without enabling reports`() {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setBody("""{"network_trusted_cache_access":true,"network_trusted_report_publishing":false}"""))
            server.enqueue(MockResponse().setBody("""{"endpoint":"${server.url("/")}"}"""))
            server.enqueue(MockResponse().setBody("cached entry"))
            val http = TuistHttpClient(provider(server.url("/").toString(), endpoint = " "), TuistHttpClients(useEnvironmentProxy = false))
            val body = http.execute { config ->
                assertEquals("", config.token)
                assertEquals("acme", config.accountHandle)
                assertEquals("widgets", config.projectHandle)
                http.openConnection(java.net.URI(config.url).resolve("/entry"), config).inputStream.bufferedReader().use { it.readText() }
            }
            assertEquals("cached entry", body)
            for (path in listOf("/.well-known/tuist.json", "/api/cache/endpoint", "/entry")) {
                val request = server.takeRequest()
                assertEquals(path, request.path)
                assertNull(request.getHeader("Authorization"))
                assertNull(request.getHeader("x-tuist-actor-id"))
            }
        }
    }

    @Test fun `report-only old disabled malformed and redirected policies never grant cache access`() {
        MockWebServer().use { server ->
            server.start()
            for (body in listOf("{}", """{"network_trusted_report_publishing":true}""", """{"network_trusted_cache_access":false}""",
                """{"network_trusted_cache_access":"true"}""", """{"network_trusted_cache_access":1}""", "not json")) {
                server.enqueue(MockResponse().setBody(body))
                assertFailsWith<Exception> { provider(server.url("/").toString()).getConfiguration() }
                assertEquals("/.well-known/tuist.json", server.takeRequest().path)
            }
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", "/other"))
            assertFailsWith<Exception> { provider(server.url("/").toString()).getConfiguration() }
            assertEquals("/.well-known/tuist.json", server.takeRequest().path)
            assertEquals(7, server.requestCount)
        }
    }

    @Test fun `unsigned endpoint overrides require policy and self hosted destinations`() {
        MockWebServer().use { server ->
            server.start()
            val url = server.url("/").toString()
            for (endpoint in listOf("https://private-cache.example", "https://acme.cache.tuist.dev")) {
                server.enqueue(MockResponse().setBody("""{"network_trusted_cache_access":true}"""))
                if (endpoint.contains("tuist.dev")) {
                    assertFailsWith<IllegalStateException> { provider(url, endpoint = endpoint).getConfiguration() }
                } else {
                    val config = provider(url, endpoint = endpoint).getConfiguration()
                    assertEquals(endpoint, config.url)
                    assertEquals("", config.token)
                }
                assertEquals("/.well-known/tuist.json", server.takeRequest().path)
            }
            server.enqueue(MockResponse().setBody("""{"network_trusted_cache_access":false}"""))
            assertFailsWith<TokenProvider.NotAuthenticatedException> {
                provider(url, endpoint = "https://private-cache.example").getConfiguration()
            }
            assertEquals("/.well-known/tuist.json", server.takeRequest().path)
            assertEquals(3, server.requestCount)
        }
    }

    @Test fun `blank credentials never fall back to network trust`() {
        MockWebServer().use { server ->
            server.start()
            assertFailsWith<Exception> { provider(server.url("/").toString(), "").getConfiguration() }
            assertEquals(0, server.requestCount)
        }
    }
}
