package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.AuthenticationTokens
import dev.tuist.gradle.services.RefreshAuthTokenService
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.net.ConnectException
import java.net.URI
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class TokenProviderTest {

    @TempDir
    lateinit var tempDir: File

    private val serverURL = URI.create("https://tuist.dev")

    private fun createCredentialStore(): CredentialStore =
        CredentialStore(File(tempDir, "credentials"))

    private fun createJwt(expSeconds: Long): String {
        val header = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("""{"alg":"HS256","typ":"JWT"}""".toByteArray())
        val payload = Base64.getUrlEncoder().withoutPadding()
            .encodeToString(Gson().toJson(mapOf("exp" to expSeconds)).toByteArray())
        val signature = Base64.getUrlEncoder().withoutPadding()
            .encodeToString("sig".toByteArray())
        return "$header.$payload.$signature"
    }

    private fun validJwt(): String = createJwt(System.currentTimeMillis() / 1000 + 3600)
    private fun expiredJwt(): String = createJwt(System.currentTimeMillis() / 1000 - 3600)

    private fun writeCredentials(
        store: CredentialStore,
        accessToken: String,
        refreshToken: String? = null
    ) {
        store.write(serverURL, Credentials(accessToken, refreshToken))
    }

    private fun createProvider(
        envVars: Map<String, String> = emptyMap(),
        refreshService: RefreshAuthTokenService = RefreshAuthTokenService(),
        credentialStore: CredentialStore = createCredentialStore()
    ): TokenProvider {
        return TokenProvider(
            serverURL = serverURL,
            refreshAuthTokenService = refreshService,
            credentialStore = credentialStore,
            envProvider = { envVars[it] },
            tokenCacheFactory = { CachedValueStore() }
        )
    }

    @Test
    fun `TUIST_TOKEN env var returns immediately`() {
        val provider = createProvider(envVars = mapOf("TUIST_TOKEN" to "env-token-123"))
        assertEquals("env-token-123", provider.getToken())
    }

    @Test
    fun `valid stored credential returns access token`() {
        val jwt = validJwt()
        val store = createCredentialStore()
        writeCredentials(store, jwt)
        val provider = createProvider(credentialStore = store)
        assertEquals(jwt, provider.getToken())
    }

    @Test
    fun `expired token with refresh token calls refresh and writes new credentials`() {
        val expiredToken = expiredJwt()
        val newToken = validJwt()
        val store = createCredentialStore()
        writeCredentials(store, expiredToken, "refresh-token")

        val mockRefreshService = object : RefreshAuthTokenService() {
            override fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
                return AuthenticationTokens(newToken, "new-refresh")
            }
        }

        val provider = createProvider(refreshService = mockRefreshService, credentialStore = store)
        assertEquals(newToken, provider.getToken())

        val stored = store.read(serverURL)
        assertEquals(newToken, stored?.accessToken)
        assertEquals("new-refresh", stored?.refreshToken)
    }

    @Test
    fun `expired token without refresh token throws NotAuthenticatedException`() {
        val store = createCredentialStore()
        writeCredentials(store, expiredJwt(), null)
        val provider = createProvider(credentialStore = store)

        assertFailsWith<TokenProvider.NotAuthenticatedException> {
            provider.getToken()
        }
    }

    @Test
    fun `no stored credentials throws NotAuthenticatedException`() {
        val store = CredentialStore(File(tempDir, "empty-credentials"))
        val provider = createProvider(credentialStore = store)

        assertFailsWith<TokenProvider.NotAuthenticatedException> {
            provider.getToken()
        }
    }

    @Test
    fun `refresh failure throws NotAuthenticatedException`() {
        val store = createCredentialStore()
        writeCredentials(store, expiredJwt(), "refresh-token")

        val failingRefreshService = object : RefreshAuthTokenService() {
            override fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
                throw RuntimeException("refresh failed")
            }
        }

        val provider = createProvider(refreshService = failingRefreshService, credentialStore = store)

        assertFailsWith<TokenProvider.NotAuthenticatedException> {
            provider.getToken()
        }
    }

    @Test
    fun `ConnectException is rethrown directly`() {
        val store = createCredentialStore()
        writeCredentials(store, expiredJwt(), "refresh-token")

        val connectExceptionService = object : RefreshAuthTokenService() {
            override fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
                throw ConnectException("Connection refused")
            }
        }

        val provider = createProvider(refreshService = connectExceptionService, credentialStore = store)

        assertFailsWith<ConnectException> {
            provider.getToken()
        }
    }

    @ParameterizedTest
    @ValueSource(booleans = [false, true])
    fun `independent providers sharing credentials refresh without losing the session`(trailingSlash: Boolean) {
        val url = URI.create("https://${tempDir.name}.example")
        val store = createCredentialStore()
        store.write(url, Credentials(expiredJwt(), "old-refresh"))
        val newToken = validJwt()
        val refreshing = CountDownLatch(1)
        val release = CountDownLatch(1)
        val revoked = AtomicBoolean(false)
        val service = object : RefreshAuthTokenService() {
            override fun refreshTokens(serverURL: URI, refreshToken: String): AuthenticationTokens {
                check(refreshToken == "old-refresh" && !revoked.getAndSet(true)) { "Refresh token revoked" }
                refreshing.countDown()
                check(release.await(5, TimeUnit.SECONDS))
                return AuthenticationTokens(newToken, "new-refresh")
            }
        }
        val first = TokenProvider(url, service, store, envProvider = { null })
        val second = TokenProvider(
            URI.create(url.toString() + if (trailingSlash) "/" else ""),
            service,
            store,
            envProvider = { null }
        )
        val executor = Executors.newFixedThreadPool(2)
        val secondResult = FutureTask<String> { second.getToken() }
        val secondThread = Thread(secondResult)
        try {
            val firstResult = executor.submit<String> { first.getToken() }
            assertTrue(refreshing.await(5, TimeUnit.SECONDS))
            secondThread.start()
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            // Observe the blocking native lock, Windows overlap retry, or the original implementation's failure.
            fun contending() = secondThread.stackTrace.any { it.methodName == "flock" } ||
                secondThread.state == Thread.State.TIMED_WAITING
            while (!secondResult.isDone && !contending() && System.nanoTime() < deadline) Thread.yield()
            assertTrue(secondResult.isDone || contending(), "Second provider never reached the refresh lock")
            release.countDown()
            assertEquals(newToken, firstResult.get(5, TimeUnit.SECONDS))
            assertEquals(newToken, secondResult.get(5, TimeUnit.SECONDS))
            assertEquals(Credentials(newToken, "new-refresh"), store.read(url))
        } finally {
            release.countDown()
            secondThread.interrupt()
            secondThread.join(5000)
            executor.shutdownNow()
        }
    }
}
