package dev.tuist.gradle

import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.IOException
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
        CachedValueStore(lockFilePath = credentialStore.refreshLockFile(url))
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
            // Only a refresh takes the cross-process lock. Its flock goes through JNA, which runs
            // `ldconfig -p` the first time it loads on Linux, and Gradle refuses to store the
            // configuration cache after a process starts while it configures, as build cache
            // lookups for compiled build scripts do.
            val token = tokenCache.getValue(
                forceRefresh,
                deadlineNanos,
                current = { if (forceRefresh) null else validStoredToken() }
            ) { resolveToken(deadlineNanos) }
            if (token.isBlank()) throw NotAuthenticatedException(serverURL)
            token
        } catch (e: TimeoutException) {
            throw InterruptedIOException("Timed out acquiring a Tuist token").apply { initCause(e) }
        }
    }

    open fun getOptionalToken(forceRefresh: Boolean = false): String? {
        if (envProvider("TUIST_TOKEN") == null && credentialStore.readValidated(serverURL) == null) return null
        return getToken(forceRefresh)
    }

    /** The stored access token while it has not expired, or `null` when it needs a refresh. */
    private fun validStoredToken(): Pair<String, Long?>? {
        val accessToken = (credentialStore.readValidated(serverURL) ?: throw NotAuthenticatedException(serverURL)).accessToken
        if (JwtParser.isExpired(accessToken)) return null
        return Pair(accessToken, JwtParser.getExpirationMs(accessToken))
    }

    private fun resolveToken(deadlineNanos: Long?): Pair<String, Long?> {
        val credentials = credentialStore.readValidated(serverURL)
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
            // A login or signout can change credentials while the refresh request is in flight.
            val currentCredentials = credentialStore.readValidated(serverURL)
                ?: throw NotAuthenticatedException(serverURL)
            if (currentCredentials != credentials) {
                return Pair(currentCredentials.accessToken, JwtParser.getExpirationMs(currentCredentials.accessToken))
            }
            credentialStore.write(
                serverURL,
                credentials.copy(accessToken = newTokens.accessToken, refreshToken = newTokens.refreshToken)
            )
            return Pair(newTokens.accessToken, JwtParser.getExpirationMs(newTokens.accessToken))
        } catch (e: IOException) {
            // Transport failures and unavailable servers say nothing about the credentials.
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
