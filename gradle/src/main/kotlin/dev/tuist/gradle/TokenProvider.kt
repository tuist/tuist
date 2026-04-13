package dev.tuist.gradle

import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.net.URI

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
    },
    internal val proxy: Proxy = Proxy.None
) {
    constructor(serverURL: URI, proxy: Proxy) : this(
        serverURL = serverURL,
        refreshAuthTokenService = RefreshAuthTokenService(proxy),
        proxy = proxy
    )

    private val tokenCache: CachedValueStore<String> by lazy {
        tokenCacheFactory(serverURL)
    }

    open fun getToken(forceRefresh: Boolean = false): String {
        val envToken = envProvider("TUIST_TOKEN")
        if (!envToken.isNullOrBlank()) return envToken

        return tokenCache.getValue(forceRefresh) { resolveToken() }
    }

    private fun resolveToken(): Pair<String, Long?> {
        val credentials = credentialStore.read(serverURL)
            ?: throw NotAuthenticatedException()

        val accessToken = credentials.accessToken
        if (!JwtParser.isExpired(accessToken)) {
            return Pair(accessToken, JwtParser.getExpirationMs(accessToken))
        }

        val refreshToken = credentials.refreshToken
        if (refreshToken.isNullOrBlank()) {
            throw NotAuthenticatedException()
        }

        try {
            val newTokens = refreshAuthTokenService.refreshTokens(serverURL, refreshToken)
            credentialStore.write(
                serverURL,
                Credentials(newTokens.accessToken, newTokens.refreshToken)
            )
            return Pair(newTokens.accessToken, JwtParser.getExpirationMs(newTokens.accessToken))
        } catch (e: java.net.ConnectException) {
            throw e
        } catch (_: Exception) {
            throw NotAuthenticatedException()
        }
    }

    class NotAuthenticatedException : RuntimeException(
        "Not authenticated with Tuist. Run `tuist auth login` or set the TUIST_TOKEN environment variable. " +
            "See https://docs.tuist.dev/en/guides/develop/build/cache#authentication"
    )
}
