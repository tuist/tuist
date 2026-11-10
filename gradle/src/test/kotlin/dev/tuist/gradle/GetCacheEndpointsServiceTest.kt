package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.services.GetCacheEndpointsService
import dev.tuist.gradle.services.RefreshAuthTokenService
import okhttp3.Call
import okhttp3.EventListener
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertTimeoutPreemptively
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.io.File
import java.io.InterruptedIOException
import java.net.URI
import java.time.Duration
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class GetCacheEndpointsServiceTest {

    @TempDir
    lateinit var tempDir: File

    private lateinit var server: MockWebServer
    private lateinit var serverURL: URI
    private val httpClients = TuistHttpClients(useEnvironmentProxy = false, environmentVariables = emptyMap())

    @BeforeEach
    fun setup() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path?.startsWith("/api/auth/refresh_token") == true -> MockResponse()
                    .setBody("""{"access_token":"${jwt(expiresInSeconds = 3600)}","refresh_token":"new-refresh"}""")
                    .setHeadersDelay(REFRESH_DELAY_MS, TimeUnit.MILLISECONDS)
                else -> MockResponse().setBody("""{"endpoints":[],"provisioning":true}""")
            }
        }
        server.start()
        serverURL = server.url("/").toUri()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `retries a 503 and returns the endpoints`() {
        MockWebServer().use { endpoints ->
            endpoints.enqueue(MockResponse().setResponseCode(503))
            endpoints.enqueue(MockResponse().setBody("""{"endpoints":["https://cache.example.com"]}"""))
            val url = endpoints.url("/").toUri()
            val tokenProvider = TokenProvider(serverURL = url, envProvider = { if (it == "TUIST_TOKEN") "token" else null })
            val service = GetCacheEndpointsService(
                TuistHttpClients(useEnvironmentProxy = false, environmentVariables = emptyMap(), retryPolicy = RetryPolicy(sleeper = {}))
            )

            val result = service.getCacheEndpoints(url, "acme", tokenProvider)

            assertEquals(listOf("https://cache.example.com"), result.endpoints)
            assertEquals(2, endpoints.requestCount)
        }
    }

    @Test
    fun `a token refresh does not outlast the call timeout`() {
        val credentialStore = CredentialStore(File(tempDir, "credentials"))
        credentialStore.write(serverURL, Credentials(jwt(expiresInSeconds = -3600), "refresh-token"))

        assertBoundedByTimeout(tokenProvider(credentialStore, lockFile = null))
    }

    @Test
    fun `waiting for a token lock held by another process does not outlast the call timeout`() {
        val credentialStore = CredentialStore(File(tempDir, "credentials"))
        credentialStore.write(serverURL, Credentials(jwt(expiresInSeconds = 3600)))
        val lockFile = File(tempDir, "token.lock")
        val holder = FileLockHolder.start(lockFile)

        try {
            assertBoundedByTimeout(tokenProvider(credentialStore, lockFile))
        } finally {
            holder.destroy()
            holder.waitFor()
        }
    }

    @Test
    fun `the token deadline counts from the start of the call`() {
        var tokenRequestedAtNanos = 0L
        var observedDeadlineNanos: Long? = null
        val tokenProvider = object : TokenProvider(serverURL, httpClients) {
            override fun getToken(forceRefresh: Boolean, deadlineNanos: Long?): String {
                tokenRequestedAtNanos = System.nanoTime()
                observedDeadlineNanos = deadlineNanos
                return "token"
            }
        }
        val client = OkHttpClient.Builder()
            .eventListener(object : EventListener() {
                override fun callStart(call: Call) {
                    Thread.sleep(CALL_START_DELAY_MS)
                }
            })
            .addInterceptor(AuthInterceptor(tokenProvider))
            .build()
        val service = GetCacheEndpointsService { url, _ ->
            Retrofit.Builder()
                .baseUrl(url.toString())
                .client(client)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
        }

        service.getCacheEndpoints(serverURL, "acme", tokenProvider, timeoutMs = REFRESH_DELAY_MS)

        val remainingMs = TimeUnit.NANOSECONDS.toMillis(assertNotNull(observedDeadlineNanos) - tokenRequestedAtNanos)
        assertTrue(
            remainingMs <= REFRESH_DELAY_MS - CALL_START_DELAY_MS,
            "The token had ${remainingMs}ms left, ${CALL_START_DELAY_MS}ms after a call with a ${REFRESH_DELAY_MS}ms timeout started"
        )
    }

    private fun assertBoundedByTimeout(tokenProvider: TokenProvider) {
        val service = GetCacheEndpointsService(httpClients)
        warmUp(service)
        assertTimeoutPreemptively(Duration.ofMillis(REFRESH_DELAY_MS * 2)) {
            val start = System.nanoTime()
            assertFailsWith<InterruptedIOException> {
                service.getCacheEndpoints(serverURL, "acme", tokenProvider, timeoutMs = TIMEOUT_MS)
            }
            val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            assertTrue(elapsedMs < TIMEOUT_MS + SLACK_MS, "The call took ${elapsedMs}ms with a ${TIMEOUT_MS}ms timeout")
        }
    }

    /**
     * Loads the HTTP client classes with a successful call, so the measured call does not include
     * the one-time class loading that runs before its timeout starts.
     */
    private fun warmUp(service: GetCacheEndpointsService) {
        val credentialStore = CredentialStore(File(tempDir, "warm-up-credentials"))
        credentialStore.write(serverURL, Credentials(jwt(expiresInSeconds = 3600)))
        service.getCacheEndpoints(
            serverURL,
            "acme",
            tokenProvider(credentialStore, File(tempDir, "warm-up.lock")),
            timeoutMs = REFRESH_DELAY_MS
        )
    }

    private fun tokenProvider(credentialStore: CredentialStore, lockFile: File?) = TokenProvider(
        serverURL = serverURL,
        refreshAuthTokenService = RefreshAuthTokenService(httpClients),
        credentialStore = credentialStore,
        envProvider = { null },
        tokenCacheFactory = { CachedValueStore(lockFilePath = lockFile) }
    )

    private fun jwt(expiresInSeconds: Long): String {
        val encoder = Base64.getUrlEncoder().withoutPadding()
        val header = encoder.encodeToString("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val payload = encoder.encodeToString(
            Gson().toJson(mapOf("exp" to System.currentTimeMillis() / 1000 + expiresInSeconds)).toByteArray()
        )
        return "$header.$payload.${encoder.encodeToString("sig".toByteArray())}"
    }

    private companion object {
        const val TIMEOUT_MS = 200L
        const val SLACK_MS = 500L
        const val REFRESH_DELAY_MS = 3_000L
        const val CALL_START_DELAY_MS = 100L
    }
}
