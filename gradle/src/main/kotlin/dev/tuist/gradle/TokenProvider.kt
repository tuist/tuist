package dev.tuist.gradle

import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.net.URI
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption

open class TokenProvider(
    private val serverURL: URI,
    internal var refreshAuthTokenService: RefreshAuthTokenService = RefreshAuthTokenService()
) {
    private val tokenCache = CachedValueStore<String>(
        isExpired = { JwtParser.isExpired(it) }
    )

    open fun getToken(forceRefresh: Boolean = false): String {
        val envToken = System.getenv("TUIST_TOKEN")
        if (!envToken.isNullOrBlank()) return envToken

        return tokenCache.getValue(forceRefresh) {
            withFileLock { resolveToken() }
        }
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

    private fun withFileLock(action: () -> String): String {
        val lockDir = File(System.getProperty("user.home"), ".tuist/state/auth-locks")
        lockDir.mkdirs()
        val sanitizedUrl = serverURL.toString().replace(Regex("[/: ]"), "_")
        val lockFile = File(lockDir, "token_$sanitizedUrl.lock")

        if (lockFile.exists() && System.currentTimeMillis() - lockFile.lastModified() > 10_000) {
            lockFile.delete()
        }

        val channel = FileChannel.open(
            lockFile.toPath(),
            StandardOpenOption.CREATE,
            StandardOpenOption.WRITE
        )
        var fileLock: FileLock? = null
        val deadline = System.currentTimeMillis() + 15_000

        try {
            while (System.currentTimeMillis() < deadline) {
                fileLock = try {
                    channel.tryLock()
                } catch (_: Exception) {
                    null
                }
                if (fileLock != null) break
                Thread.sleep(500)
            }

            if (fileLock == null) {
                throw RuntimeException("Timed out waiting for auth lock")
            }

            val freshCredentials = CredentialStore.read(serverURL)
            if (freshCredentials != null && !JwtParser.isExpired(freshCredentials.accessToken)) {
                return freshCredentials.accessToken
            }

            return action()
        } finally {
            fileLock?.release()
            channel.close()
        }
    }
}
