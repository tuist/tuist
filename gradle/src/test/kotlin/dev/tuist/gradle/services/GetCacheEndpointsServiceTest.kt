package dev.tuist.gradle.services

import com.google.gson.Gson
import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.TokenProvider
import dev.tuist.gradle.api.model.CacheEndpoints
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GetCacheEndpointsServiceTest {

    private lateinit var mockServer: MockWebServer

    @BeforeEach
    fun setup() {
        mockServer = MockWebServer()
        mockServer.start()
    }

    @AfterEach
    fun tearDown() {
        mockServer.shutdown()
    }

    private fun createService(): GetCacheEndpointsService {
        return GetCacheEndpointsService { url, tokenProvider ->
            ServerClient.authenticated(url, tokenProvider)
        }
    }

    @Test
    fun `getCacheEndpoints sends GET to correct path with account_handle query param`() {
        val responseBody = Gson().toJson(CacheEndpoints(listOf("https://cache1.tuist.dev", "https://cache2.tuist.dev")))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val tokenProvider = object : TokenProvider(mockServer.url("/").toUri()) {
            override fun getToken(forceRefresh: Boolean): String = "test-auth-token"
        }

        val service = createService()
        val result = service.getCacheEndpoints(
            mockServer.url("/").toUri(),
            "my-account",
            tokenProvider
        )

        assertEquals(2, result.size)
        assertEquals("https://cache1.tuist.dev", result[0])
        assertEquals("https://cache2.tuist.dev", result[1])

        val request = mockServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.startsWith("/api/cache/endpoints"))
        assertTrue(request.path!!.contains("account_handle=my-account"))
    }

    @Test
    fun `getCacheEndpoints sends auth header`() {
        val responseBody = Gson().toJson(CacheEndpoints(listOf("https://cache.tuist.dev")))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val tokenProvider = object : TokenProvider(mockServer.url("/").toUri()) {
            override fun getToken(forceRefresh: Boolean): String = "my-bearer-token"
        }

        val service = createService()
        service.getCacheEndpoints(
            mockServer.url("/").toUri(),
            "account",
            tokenProvider
        )

        val request = mockServer.takeRequest()
        assertEquals("Bearer my-bearer-token", request.getHeader("Authorization"))
    }

    @Test
    fun `getCacheEndpoints throws with server error message on 401`() {
        mockServer.enqueue(MockResponse().setResponseCode(401).setBody("Authentication required"))

        val tokenProvider = object : TokenProvider(mockServer.url("/").toUri()) {
            override fun getToken(forceRefresh: Boolean): String = "expired-token"
        }

        val service = createService()
        val error = assertThrows<GetCacheEndpointsServiceError> {
            service.getCacheEndpoints(
                mockServer.url("/").toUri(),
                "account",
                tokenProvider
            )
        }
        assertEquals("Authentication required", error.message)
    }

    @Test
    fun `getCacheEndpoints throws on network error`() {
        val tokenProvider = object : TokenProvider(java.net.URI.create("http://localhost:1")) {
            override fun getToken(forceRefresh: Boolean): String = "token"
        }

        val service = createService()
        assertThrows<Exception> {
            service.getCacheEndpoints(
                java.net.URI.create("http://localhost:1"),
                "account",
                tokenProvider
            )
        }
    }
}
