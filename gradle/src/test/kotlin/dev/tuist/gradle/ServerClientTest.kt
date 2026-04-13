package dev.tuist.gradle

import dev.tuist.gradle.api.AuthenticationApi
import dev.tuist.gradle.api.model.RefreshTokenBody
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals

class ServerClientTest {

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

    @Test
    fun `unauthenticated routes requests through the configured proxy`() {
        // The mock web server plays the role of the HTTP proxy. If `ServerClient`
        // applies the proxy correctly, the Retrofit/OkHttp client should route even
        // requests to a fake `.invalid` hostname through the mock — no DNS lookup,
        // no real network traffic.
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val retrofit = ServerClient.unauthenticated(
            serverURL = URI("http://tuist-proxy-test.invalid"),
            proxy = Proxy.Url(mockProxy.url("/").toString().trimEnd('/'))
        )
        val api = retrofit.create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
    }

    @Test
    fun `authenticated routes requests through the configured proxy`() {
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val tokenProvider = object : TokenProvider(URI("http://tuist-proxy-test.invalid")) {
            override fun getToken(forceRefresh: Boolean): String = "test-token"
        }

        val retrofit = ServerClient.authenticated(
            serverURL = URI("http://tuist-proxy-test.invalid"),
            tokenProvider = tokenProvider,
            proxy = Proxy.Url(mockProxy.url("/").toString().trimEnd('/'))
        )
        val api = retrofit.create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
    }

    @Test
    fun `no proxy hits the target server directly`() {
        // Swap roles: the mock web server is now the actual target. With `Proxy.None`
        // the client should talk to it directly.
        mockProxy.enqueue(MockResponse().setResponseCode(200).setBody("""{"access_token":"at","refresh_token":"rt"}"""))

        val retrofit = ServerClient.unauthenticated(
            serverURL = URI(mockProxy.url("/").toString().trimEnd('/')),
            proxy = Proxy.None
        )
        val api = retrofit.create(AuthenticationApi::class.java)

        api.refreshToken(RefreshTokenBody("any")).execute()

        assertEquals(1, mockProxy.requestCount)
    }
}
