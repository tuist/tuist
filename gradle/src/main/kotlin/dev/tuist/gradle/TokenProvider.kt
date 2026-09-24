package dev.tuist.gradle

import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.io.InterruptedIOException
import java.net.URI
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

open class TokenProvider(
    private val serverURL: URI,
    internal var refreshAuthTokenService: RefreshAuthTokenService = RefreshAuthTokenService(),
    internal val credentialStore: CredentialStore = CredentialStore(),
    internal val envProvider: (String) -> String? = { System.getenv(it) },
    internal val tokenCacheFactory: (URI) -> CachedValueStore<String> = { url ->
        val sanitizedUrl = URI(url.scheme, url.host, url.path, null).toASCIIString()
            .replace(Regex("[/: ]"), "_")
        CachedValueStore(
            lockFilePath = File(
                File(System.getProperty("user.home"), ".tuist/state/auth-locks"),
                "token_$sanitizedUrl.lock"
            )
        )
    }
) {
    /** Convenience constructor: wires an internal [RefreshAuthTokenService] from the given [httpClients]. */
    constructor(serverURL: URI, httpClients: TuistHttpClients) : this(
        serverURL = serverURL,
        refreshAuthTokenService = RefreshAuthTokenService(httpClients)
    )

    private val tokenCache: CachedValueStore<String> by lazy {
        tokenCacheFactory(serverURL)
    }

    /**
     * @param deadlineNanos a [System.nanoTime] by which to have a token, covering the wait for a
     * refresh another caller started, the lock that serializes refreshes across processes, and the
     * refresh request. Past it, fails with an [InterruptedIOException]. `null` waits for as long
     * as it takes.
     */
    open fun getToken(forceRefresh: Boolean = false, deadlineNanos: Long? = null): String {
        val envToken = envProvider("TUIST_TOKEN")
        if (!envToken.isNullOrBlank()) return envToken

        return try {
            tokenCache.getValue(forceRefresh, deadlineNanos) { resolveToken(deadlineNanos) }
        } catch (e: TimeoutException) {
            throw InterruptedIOException("Timed out acquiring a Tuist token").apply { initCause(e) }
        }
    }

    private fun resolveToken(deadlineNanos: Long?): Pair<String, Long?> {
        val credentials = credentialStore.read(serverURL)
            ?: throw NotAuthenticatedException(serverURL)

        val accessToken = credentials.accessToken
        if (!JwtParser.isExpired(accessToken)) {
            return Pair(accessToken, JwtParser.getExpirationMs(accessToken))
        }

        val refreshToken = credentials.refreshToken
        if (refreshToken.isNullOrBlank()) {
            throw NotAuthenticatedException(serverURL)
        }

        val timeoutMs = deadlineNanos?.let {
            val remainingMs = TimeUnit.NANOSECONDS.toMillis(it - System.nanoTime())
            if (remainingMs <= 0) throw InterruptedIOException("Timed out before refreshing the Tuist token")
            remainingMs
        }

        try {
            val newTokens = refreshAuthTokenService.refreshTokens(serverURL, refreshToken, timeoutMs)
            credentialStore.write(
                serverURL,
                Credentials(newTokens.accessToken, newTokens.refreshToken)
            )
            return Pair(newTokens.accessToken, JwtParser.getExpirationMs(newTokens.accessToken))
        } catch (e: java.net.ConnectException) {
            throw e
        } catch (e: InterruptedIOException) {
            throw e
        } catch (_: Exception) {
            throw NotAuthenticatedException(serverURL)
        }
    }

    class NotAuthenticatedException(serverURL: URI) : RuntimeException(
        "Not authenticated with Tuist. Run `tuist auth login --url $serverURL` or set the TUIST_TOKEN environment variable. " +
            "See https://tuist.dev/en/docs/guides/install-gradle-plugin#authenticate"
    )
}
