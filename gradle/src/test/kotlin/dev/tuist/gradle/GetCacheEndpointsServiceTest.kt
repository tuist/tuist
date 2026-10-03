package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.services.GetCacheEndpointsService
import dev.tuist.gradle.services.RefreshAuthTokenService
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertTimeoutPreemptively
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.io.InterruptedIOException
import java.net.URI
import java.time.Duration
import java.util.Base64
import java.util.concurrent.TimeUnit
import kotlin.test.assertFailsWith
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

    private fun assertBoundedByTimeout(tokenProvider: TokenProvider) {
        val service = GetCacheEndpointsService(httpClients)
        assertTimeoutPreemptively(Duration.ofMillis(REFRESH_DELAY_MS * 2)) {
            val start = System.nanoTime()
            assertFailsWith<InterruptedIOException> {
                service.getCacheEndpoints(serverURL, "acme", tokenProvider, timeoutMs = TIMEOUT_MS)
            }
            val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - start)
            assertTrue(elapsedMs < TIMEOUT_MS + SLACK_MS, "The call took ${elapsedMs}ms with a ${TIMEOUT_MS}ms timeout")
        }
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
    }
}
