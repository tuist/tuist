package dev.tuist.app.data.network

import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.auth.AuthEvent
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.every
import io.mockk.mockk
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.IOException
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
class TokenRefreshAuthenticatorTest {

    private lateinit var server: MockWebServer
    private lateinit var tokenStorage: TokenStorage
    private val authEvents = Collections.synchronizedList(mutableListOf<AuthEvent>())
    private lateinit var client: OkHttpClient

    @Volatile private var storedAccessToken: String? = "old-access"
    @Volatile private var storedRefreshToken: String? = "old-refresh"
    private val refreshRequests = Collections.synchronizedList(mutableListOf<RecordedRequest>())
    private val refreshCount = AtomicInteger(0)
    @Volatile private var refreshResponse: (RecordedRequest) -> MockResponse = { successfulRefresh() }

    @Before
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when (request.path) {
                "/oauth2/token" -> {
                    refreshCount.incrementAndGet()
                    refreshRequests.add(request)
                    refreshResponse(request)
                }
                else -> if (request.getHeader("Authorization") == "Bearer new-access") {
                    MockResponse().setResponseCode(200).setBody("{}")
                } else {
                    MockResponse().setResponseCode(401)
                }
            }
        }
        server.start()

        tokenStorage = mockk {
            every { getAccessToken() } answers { storedAccessToken }
            every { getRefreshToken() } answers { storedRefreshToken }
            every { storeTokens(any(), any()) } answers {
                storedAccessToken = firstArg()
                storedRefreshToken = secondArg()
            }
            every { clear() } answers {
                storedAccessToken = null
                storedRefreshToken = null
            }
        }
        val environmentConfig = mockk<EnvironmentConfig> {
            every { serverUrl } returns server.url("/").toString().trimEnd('/')
            every { oauthClientId } returns "client-id"
        }
        val authEventBus = mockk<AuthEventBus> {
            every { emit(any()) } answers { authEvents.add(firstArg()) }
        }

        val authenticator = TokenRefreshAuthenticator(
            tokenStorage = tokenStorage,
            plainClient = OkHttpClient(),
            environmentConfig = environmentConfig,
            authEventBus = authEventBus,
        )
        client = OkHttpClient.Builder()
            .addInterceptor(AuthInterceptor(tokenStorage))
            .authenticator(authenticator)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `rotates tokens through the OAuth token endpoint and retries the request`() {
        val response = execute()

        assertEquals(200, response.code)
        assertEquals("new-access", storedAccessToken)
        assertEquals("new-refresh", storedRefreshToken)
        val refreshRequest = refreshRequests.single()
        assertEquals("POST", refreshRequest.method)
        assertEquals(
            "grant_type=refresh_token&refresh_token=old-refresh&client_id=client-id",
            refreshRequest.body.readUtf8(),
        )
    }

    @Test
    fun `clears tokens when the refresh token is rejected with invalid_grant`() {
        refreshResponse = { invalidGrant() }

        val response = execute()

        assertEquals(401, response.code)
        assertNull(storedAccessToken)
        assertNull(storedRefreshToken)
        assertEquals(listOf(AuthEvent.SessionExpired), authEvents)
    }

    @Test
    fun `clears tokens when the refresh request is unauthorized`() {
        refreshResponse = { MockResponse().setResponseCode(401).setBody("""{"error":"invalid_client"}""") }

        execute()

        assertNull(storedAccessToken)
        assertNull(storedRefreshToken)
    }

    @Test
    fun `keeps tokens rotated concurrently when the refresh token is rejected`() {
        refreshResponse = {
            storedAccessToken = "new-access"
            storedRefreshToken = "concurrent-refresh"
            invalidGrant()
        }

        val response = execute()

        assertEquals(200, response.code)
        assertEquals("new-access", storedAccessToken)
        assertEquals("concurrent-refresh", storedRefreshToken)
        assertTrue(authEvents.isEmpty())
    }

    @Test
    fun `keeps tokens when the refresh request fails with a network error`() {
        refreshResponse = { MockResponse().setSocketPolicy(SocketPolicy.DISCONNECT_AT_START) }

        assertThrows(IOException::class.java) { execute() }

        assertEquals("old-access", storedAccessToken)
        assertEquals("old-refresh", storedRefreshToken)
        assertTrue(authEvents.isEmpty())
    }

    @Test
    fun `keeps tokens when the refresh request fails with a server error`() {
        for (code in listOf(408, 429, 500, 503)) {
            refreshResponse = { MockResponse().setResponseCode(code) }

            assertThrows(TokenRefreshException::class.java) { execute() }

            assertEquals("old-access", storedAccessToken)
            assertEquals("old-refresh", storedRefreshToken)
        }
        assertTrue(authEvents.isEmpty())
    }

    @Test
    fun `retries the next request after a transient refresh failure`() {
        refreshResponse = { MockResponse().setResponseCode(503) }
        assertThrows(TokenRefreshException::class.java) { execute() }

        refreshResponse = { successfulRefresh() }
        val response = execute()

        assertEquals(200, response.code)
        assertEquals("new-access", storedAccessToken)
    }

    @Test
    fun `coalesces concurrent unauthorized responses into a single refresh`() {
        refreshResponse = {
            Thread.sleep(200)
            successfulRefresh()
        }
        val executor = Executors.newFixedThreadPool(4)

        val codes = (1..4)
            .map { executor.submit<Int> { execute().code } }
            .map { it.get(10, TimeUnit.SECONDS) }
        executor.shutdown()

        assertTrue(codes.all { it == 200 })
        assertEquals(1, refreshCount.get())
    }

    private fun execute() = client.newCall(
        Request.Builder().url(server.url("/api/projects")).build(),
    ).execute().use { it }

    private fun successfulRefresh() = MockResponse()
        .setResponseCode(200)
        .setBody("""{"access_token":"new-access","refresh_token":"new-refresh","token_type":"bearer"}""")

    private fun invalidGrant() = MockResponse()
        .setResponseCode(400)
        .setBody("""{"error":"invalid_grant","error_description":"Given refresh token is invalid."}""")
}
