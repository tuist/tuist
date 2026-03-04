package dev.tuist.gradle.services

import com.google.gson.Gson
import dev.tuist.gradle.ServerClient
import dev.tuist.gradle.api.model.AuthenticationTokens
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class RefreshAuthTokenServiceTest {

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

    private fun createService(): RefreshAuthTokenService {
        return RefreshAuthTokenService { ServerClient.unauthenticated(it) }
    }

    @Test
    fun `refreshTokens sends POST to correct path with refresh token in body`() {
        val responseBody = Gson().toJson(AuthenticationTokens("new-access", "new-refresh"))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val service = createService()
        val result = service.refreshTokens(mockServer.url("/").toString(), "old-refresh-token")

        assertNotNull(result)
        assertEquals("new-access", result.accessToken)
        assertEquals("new-refresh", result.refreshToken)

        val request = mockServer.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/auth/refresh_token", request.path)
        val body = request.body.readUtf8()
        assert(body.contains("\"refresh_token\""))
        assert(body.contains("old-refresh-token"))
    }

    @Test
    fun `refreshTokens does not send auth header`() {
        val responseBody = Gson().toJson(AuthenticationTokens("access", "refresh"))
        mockServer.enqueue(MockResponse().setBody(responseBody).setResponseCode(200))

        val service = createService()
        service.refreshTokens(mockServer.url("/").toString(), "token")

        val request = mockServer.takeRequest()
        assertNull(request.getHeader("Authorization"))
    }

    @Test
    fun `refreshTokens returns null on 401`() {
        mockServer.enqueue(MockResponse().setResponseCode(401))

        val service = createService()
        val result = service.refreshTokens(mockServer.url("/").toString(), "bad-token")

        assertNull(result)
    }

    @Test
    fun `refreshTokens returns null on network error`() {
        mockServer.shutdown()

        val service = createService()
        val result = service.refreshTokens(mockServer.url("/").toString(), "token")

        assertNull(result)
    }
}
