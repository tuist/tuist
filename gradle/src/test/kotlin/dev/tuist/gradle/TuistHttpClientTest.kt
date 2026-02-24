package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertEquals

class TuistHttpClientTest {

    private lateinit var mockWebServer: MockWebServer

    @BeforeEach
    fun setup() {
        mockWebServer = MockWebServer()
        mockWebServer.start()
    }

    @AfterEach
    fun tearDown() {
        mockWebServer.shutdown()
    }

    private fun createHttpClient(token: String = "test-token"): TuistHttpClient {
        val baseUrl = mockWebServer.url("/").toString().trimEnd('/')
        return TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean): TuistCacheConfiguration = TuistCacheConfiguration(
                    url = baseUrl,
                    token = token,
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
    }

    @Test
    fun `openConnection sets Bearer token header`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val httpClient = createHttpClient(token = "my-secret-token")
        val url = URI(mockWebServer.url("/test").toString())

        httpClient.execute { config ->
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            connection.responseCode
        }

        val request = mockWebServer.takeRequest()
        assertEquals("Bearer my-secret-token", request.getHeader("Authorization"))
    }

    @Test
    fun `execute retries once on TokenExpiredException`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("ok"))

        val httpClient = createHttpClient()

        val result = httpClient.execute { config ->
            val url = URI(mockWebServer.url("/test").toString())
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            when (connection.responseCode) {
                HttpURLConnection.HTTP_OK -> "success"
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> "error"
            }
        }

        assertEquals("success", result)
        assertEquals(2, mockWebServer.requestCount)
    }

    @Test
    fun `execute returns result directly on success`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("hello"))

        val httpClient = createHttpClient()

        val result = httpClient.execute { config ->
            val url = URI(mockWebServer.url("/test").toString())
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            connection.responseCode
        }

        assertEquals(200, result)
        assertEquals(1, mockWebServer.requestCount)
    }
}
