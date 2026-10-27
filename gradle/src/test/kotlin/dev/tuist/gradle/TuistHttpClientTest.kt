package dev.tuist.gradle

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

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
                override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration = CacheConfiguration(
                    url = baseUrl,
                    token = token,
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            httpClients = TuistHttpClients(
                environmentVariables = mapOf(
                    "TUIST_FEATURE_FLAG_A" to "1"
                )
            ),
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
    fun `openConnection sets enabled feature flags header`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val httpClient = createHttpClient()
        val url = URI(mockWebServer.url("/test").toString())

        httpClient.execute { config ->
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            connection.responseCode
        }

        val request = mockWebServer.takeRequest()
        assertEquals("A", request.getHeader(FeatureFlagsHeaders.HEADER_NAME))
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
    fun `an authenticated 401 cannot retry with credentials that disappeared`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        var calls = 0
        val baseUrl = mockWebServer.url("/").toString()
        val client = TuistHttpClient(object : ConfigurationProvider {
            override fun getConfiguration(forceRefresh: Boolean): CacheConfiguration {
                calls++
                return CacheConfiguration(baseUrl, if (forceRefresh) "" else "invalid-token", "account", "project")
            }
        })
        assertFailsWith<TokenExpiredException> {
            client.execute { config ->
                val connection = client.openConnection(URI(mockWebServer.url("/report").toString()), config)
                if (connection.responseCode == 401) throw TokenExpiredException()
            }
        }
        assertEquals(2, calls)
        assertEquals(1, mockWebServer.requestCount)
        assertEquals("Bearer invalid-token", mockWebServer.takeRequest().getHeader("Authorization"))
    }

    @Test
    fun `credential-free 401 does not refresh or retry and explains server policy`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        val client = createHttpClient(token = "")
        assertFailsWith<ReportAuthenticationRequiredException> {
            client.execute { config ->
                val connection = client.openConnection(URI(mockWebServer.url("/report").toString()), config)
                if (connection.responseCode == 401) throw TokenExpiredException()
            }
        }
        assertEquals(1, mockWebServer.requestCount)
        assertNull(mockWebServer.takeRequest().getHeader("Authorization"))
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
