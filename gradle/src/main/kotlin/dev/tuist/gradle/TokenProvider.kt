package dev.tuist.gradle

import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.net.URI

open class TokenProvider(
    private val serverURL: URI,
    internal var refreshAuthTokenService: RefreshAuthTokenService = RefreshAuthTokenService()
) {
    private val tokenCache: CachedValueStore<String> by lazy {
        val sanitizedUrl = serverURL.toString().replace(Regex("[/: ]"), "_")
        CachedValueStore(
            isExpired = { JwtParser.isExpired(it) },
            lockFilePath = File(
                File(System.getProperty("user.home"), ".tuist/state/auth-locks"),
                "token_$sanitizedUrl.lock"
            ),
            readFromDisk = {
                CredentialStore.read(serverURL)?.accessToken
            }
        )
    }

    open fun getToken(forceRefresh: Boolean = false): String {
        val envToken = System.getenv("TUIST_TOKEN")
        if (!envToken.isNullOrBlank()) return envToken

        return tokenCache.getValue(forceRefresh) { resolveToken() }
    }

    private fun resolveToken(): String {
        val credentials = CredentialStore.read(serverURL)
        if (credentials != null) {
            val refreshToken = credentials.refreshToken
            if (!refreshToken.isNullOrBlank()) {
                try {
                    val newTokens = refreshAuthTokenService.refreshTokens(serverURL, refreshToken)
                    CredentialStore.write(
                        serverURL,
                        Credentials(newTokens.accessToken, newTokens.refreshToken)
                    )
                    return newTokens.accessToken
                } catch (_: Exception) {
                    // Fall through
                }
            }
        }

        throw RuntimeException(
            "Not authenticated with Tuist. Run `tuist auth login` or set the TUIST_TOKEN environment variable."
        )
    }
}
