package dev.tuist.gradle

import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.RefreshTokenBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class TuistHttpClientsTest {

    private lateinit var mockProxy: MockWebServer

    @BeforeEach
    fun setup() {
        mockProxy = MockWebServer()
        mockProxy.start()
    }

    @AfterEach
    fun tearDown() {
        mockProxy.shutdown()
    }

    private fun proxyUrl(): String = mockProxy.url("/").toString().trimEnd('/')

    @Test
    fun `NONE exposes a null javaProxy and a working OkHttp client`() {
        assertNull(TuistHttpClients.NONE.javaProxy)
        assertNotNull(TuistHttpClients.NONE.okHttp)
        assertNotNull(TuistHttpClients.NONE.latencyClient)
    }

    @Test
    fun `unauthenticatedRetrofit routes through the configured proxy`() {
        // The mock web server plays the proxy. Even though we ask Retrofit to
        // talk to `.invalid` (which would fail DNS resolution), the request
        // should land on the mock — proving the proxy is applied.
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients(Proxy.Url(proxyUrl()))
        val api = httpClients.unauthenticatedRetrofit(URI("http://tuist-proxy-test.invalid"))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
    }

    @Test
    fun `authenticatedRetrofit routes through the configured proxy and attaches the bearer token`() {
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val tokenProvider = object : TokenProvider(URI("http://tuist-proxy-test.invalid")) {
            override fun getToken(forceRefresh: Boolean): String = "secret-token"
        }

        val httpClients = TuistHttpClients(Proxy.Url(proxyUrl()))
        val api = httpClients.authenticatedRetrofit(URI("http://tuist-proxy-test.invalid"), tokenProvider)
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
        val recorded = mockProxy.takeRequest()
        assertEquals("Bearer secret-token", recorded.getHeader("Authorization"))
    }

    @Test
    fun `openConnection routes HttpURLConnection through the configured proxy`() {
        mockProxy.enqueue(MockResponse().setResponseCode(204))

        val httpClients = TuistHttpClients(Proxy.Url(proxyUrl()))
        val connection = httpClients.openConnection(URI("http://tuist-proxy-test.invalid/status"))
        connection.requestMethod = "GET"
        val code = connection.responseCode
        connection.disconnect()

        assertEquals(HttpURLConnection.HTTP_NO_CONTENT, code)
        assertEquals(1, mockProxy.requestCount)
    }

    @Test
    fun `NONE talks to the target server directly without intercepting`() {
        // Swap roles: the mock server is the actual target.
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val httpClients = TuistHttpClients.NONE
        val api = httpClients.unauthenticatedRetrofit(URI(proxyUrl()))
            .create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
    }
}
