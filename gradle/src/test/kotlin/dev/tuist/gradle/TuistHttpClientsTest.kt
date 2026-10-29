package dev.tuist.gradle

import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.RefreshTokenBody
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistHttpClientsTest {

    private lateinit var server: MockWebServer

    @BeforeEach
    fun setup() {
        server = MockWebServer()
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `exposes working OkHttp and latency clients`() {
        val httpClients = TuistHttpClients()
        assertNotNull(httpClients.okHttp)
        assertNotNull(httpClients.latencyClient)
    }

    @Test
    fun `does not create proxy when environment proxy usage is disabled`() {
        val httpClients = TuistHttpClients(
            useEnvironmentProxy = false,
            proxyURLProvider = { "http://proxy.tuist.dev:8080" }
        )

        assertNull(httpClients.javaProxy)
    }

    @Test
    fun `creates proxy from environment when enabled`() {
        val httpClients = TuistHttpClients(
            useEnvironmentProxy = true,
            proxyURLProvider = { "http://proxy.tuist.dev:8080" }
        )

        assertNotNull(httpClients.javaProxy)
    }

    @Test
    fun `unauthenticatedRetrofit reaches the target server when no proxy env var is set`() {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients()
        val api = httpClients.unauthenticatedRetrofit(URI(server.url("/").toString().trimEnd('/')))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, server.requestCount)
    }

    @Test
    fun `retrofit clients include enabled feature flags in the header when present`() {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients(
            environmentVariables = mapOf(
                "TUIST_FEATURE_FLAG_A" to "1",
                "TUIST_FEATURE_FLAG_B" to "enabled",
            )
        )
        val api = httpClients.unauthenticatedRetrofit(URI(server.url("/").toString().trimEnd('/')))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        val request = server.takeRequest()
        assertEquals("A,B", request.getHeader(FeatureFlagsHeaders.HEADER_NAME))
    }

    @Test
    fun `retrofit clients send the plugin version`() {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients(pluginVersion = "0.15.0")
        val api = httpClients.unauthenticatedRetrofit(URI(server.url("/").toString().trimEnd('/')))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        val request = server.takeRequest()
        assertEquals("0.15.0", request.getHeader(PluginVersion.HEADER_NAME))
    }

    @Test
    fun `the plugin version is the version the plugin was built with`() {
        val version = assertNotNull(PluginVersion.current)
        assertTrue(Regex("""\d+\.\d+\.\d+.*""").matches(version), "Unexpected plugin version: $version")
    }

    @Test
    fun `retrofit clients skip client feature flags header when absent`() {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients(
            environmentVariables = mapOf("TUIST_TOKEN" to "token")
        )
        val api = httpClients.unauthenticatedRetrofit(URI(server.url("/").toString().trimEnd('/')))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        val request = server.takeRequest()
        assertNull(request.getHeader(FeatureFlagsHeaders.HEADER_NAME))
    }

    @Test
    fun `retrofit clients skip client feature flags header when every flag is disabled`() {
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients(
            environmentVariables = mapOf("TUIST_FEATURE_FLAG_A" to "0")
        )
        val api = httpClients.unauthenticatedRetrofit(URI(server.url("/").toString().trimEnd('/')))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        val request = server.takeRequest()
        assertNull(request.getHeader(FeatureFlagsHeaders.HEADER_NAME))
    }

    @Test
    fun `OkHttp reuses an idle connection within the keep-alive and opens a new one after it`() {
        val client = TuistHttpClients(useEnvironmentProxy = false).okHttp
        val get = {
            server.enqueue(MockResponse().setBody("ok"))
            client.newCall(Request.Builder().url(server.url("/")).build()).execute().use { it.body?.string() }
            server.takeRequest().sequenceNumber
        }

        assertEquals(0, get())
        Thread.sleep(1_000)
        assertEquals(1, get(), "a connection idle for 1 s must be reused")
        Thread.sleep(11_000)
        assertEquals(0, client.connectionPool.idleConnectionCount(), "a connection idle past 10 s must be evicted")
        assertEquals(0, get(), "a connection idle past 10 s must not be reused")
    }

    @Test
    fun `HttpURLConnection does not reuse a connection idle past 5 s when the server sends no Keep-Alive timeout`() {
        val httpClients = TuistHttpClients(useEnvironmentProxy = false)
        val get = {
            server.enqueue(MockResponse().setBody("ok"))
            val connection = httpClients.openConnection(server.url("/").toUri())
            connection.inputStream.use { it.readBytes() }
            assertNull(connection.getHeaderField("Keep-Alive"))
            server.takeRequest().sequenceNumber
        }

        assertEquals(0, get())
        Thread.sleep(1_000)
        assertEquals(1, get(), "a connection idle for 1 s must be reused")
        Thread.sleep(6_000)
        assertEquals(0, get(), "a connection idle for 6 s must not be reused")
    }
}
