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
import kotlin.test.assertNotNull
import kotlin.test.assertNull

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
}
