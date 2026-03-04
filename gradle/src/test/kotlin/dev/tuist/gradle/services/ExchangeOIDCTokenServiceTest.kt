package dev.tuist.gradle.services

import com.google.gson.Gson
import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.model.OIDCTokenExchangeResponse
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class ExchangeOIDCTokenServiceTest {

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

    private fun createService(): ExchangeOIDCTokenService {
        return ExchangeOIDCTokenService { ServerClient.unauthenticated(it) }
    }

    @Test
    fun `exchangeOIDCToken sends POST to correct path with token in body`() {
        val responseBody = Gson().toJson(OIDCTokenExchangeResponse("tuist-access-token", 3600))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val service = createService()
        val result = service.exchangeOIDCToken(mockServer.url("/").toString(), "ci-oidc-token")

        assertNotNull(result)
        assertEquals("tuist-access-token", result)

        val request = mockServer.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/auth/oidc/token", request.path)
        val body = request.body.readUtf8()
        assert(body.contains("\"token\""))
        assert(body.contains("ci-oidc-token"))
    }

    @Test
    fun `exchangeOIDCToken does not send auth header`() {
        val responseBody = Gson().toJson(OIDCTokenExchangeResponse("token", 3600))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val service = createService()
        service.exchangeOIDCToken(mockServer.url("/").toString(), "oidc-token")

        val request = mockServer.takeRequest()
        assertNull(request.getHeader("Authorization"))
    }

    @Test
    fun `exchangeOIDCToken returns null on 401`() {
        mockServer.enqueue(MockResponse().setResponseCode(401))

        val service = createService()
        val result = service.exchangeOIDCToken(mockServer.url("/").toString(), "bad-token")

        assertNull(result)
    }

    @Test
    fun `exchangeOIDCToken returns null on network error`() {
        mockServer.shutdown()

        val service = createService()
        val result = service.exchangeOIDCToken(mockServer.url("/").toString(), "token")

        assertNull(result)
    }
}
