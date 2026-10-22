package dev.tuist.gradle

import dev.tuist.gradle.services.CacheFreeTierExhaustedException
import dev.tuist.gradle.services.GetCacheTokenService
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class GetCacheTokenServiceTest {

    private lateinit var server: MockWebServer
    private lateinit var serverURL: URI
    private val httpClients = TuistHttpClients(useEnvironmentProxy = false, environmentVariables = emptyMap())
    private val service = GetCacheTokenService(httpClients)

    @BeforeEach
    fun setup() {
        server = MockWebServer()
        server.start()
        serverURL = server.url("/").toUri()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    private fun tokenProvider() = TokenProvider(serverURL, envProvider = { if (it == "TUIST_TOKEN") "credential" else null })

    @Test
    fun `exchanges the credential for a token scoped to the project`() {
        server.enqueue(MockResponse().setBody("""{"token":"cache-token","expires_in":1800}"""))

        val cacheToken = service.getCacheToken(serverURL, "account/project", tokenProvider())

        assertEquals("cache-token", cacheToken.token)
        assertEquals(1800, cacheToken.expiresIn)
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/cache/token?full_handle=account%2Fproject", request.path)
        assertEquals("Bearer credential", request.getHeader("Authorization"))
    }

    @Test
    fun `reports an exhausted free tier with the server's message`() {
        server.enqueue(MockResponse().setResponseCode(402).setBody("""{"message":"Upgrade your plan."}"""))

        val error = assertFailsWith<CacheFreeTierExhaustedException> {
            service.getCacheToken(serverURL, "account/project", tokenProvider())
        }

        assertEquals("Upgrade your plan.", error.message)
    }

    @Test
    fun `fails on other statuses`() {
        server.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        val error = assertFailsWith<RuntimeException> {
            service.getCacheToken(serverURL, "account/project", tokenProvider())
        }

        assertEquals(RuntimeException::class, error::class)
    }

    @Test
    fun `fails when the response has no token`() {
        server.enqueue(MockResponse().setBody("{}"))

        val error = assertFailsWith<RuntimeException> {
            service.getCacheToken(serverURL, "account/project", tokenProvider())
        }

        assertEquals("The cache token response did not include a token.", error.message)
    }
}
