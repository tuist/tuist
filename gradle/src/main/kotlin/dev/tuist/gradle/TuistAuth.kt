package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.net.URI
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption

data class Credentials(
    val accessToken: String,
    val refreshToken: String? = null
)

object CredentialStore {
    val credentialsDir: File
        get() {
            val baseConfigDir = System.getenv("TUIST_XDG_CONFIG_HOME")?.takeIf { it.isNotBlank() }
                ?: System.getenv("XDG_CONFIG_HOME")?.takeIf { it.isNotBlank() }
                ?: File(System.getProperty("user.home"), ".config").path
            return File(File(baseConfigDir, "tuist"), "credentials")
        }

    fun read(serverURL: URI): Credentials? {
        val hostname = serverURL.host ?: return null
        val credFile = File(credentialsDir, "$hostname.json")
        if (!credFile.exists()) return null
        return try {
            Gson().fromJson(credFile.readText(), Credentials::class.java)
        } catch (_: Exception) {
            null
        }
    }

    fun write(serverURL: URI, credentials: Credentials) {
        val hostname = serverURL.host ?: return
        credentialsDir.mkdirs()
        File(credentialsDir, "$hostname.json").writeText(Gson().toJson(credentials))
    }
}

open class TokenProvider(
    private val serverURL: URI,
    internal var refreshAuthTokenService: RefreshAuthTokenService = RefreshAuthTokenService()
) {
    @Volatile
    private var cachedToken: String? = null
    private val lock = Any()

    open fun getToken(forceRefresh: Boolean = false): String {
        val envToken = System.getenv("TUIST_TOKEN")
        if (!envToken.isNullOrBlank()) return envToken

        if (!forceRefresh) {
            cachedToken?.let { token ->
                if (!JwtParser.isExpired(token)) return token
            }
        }

        synchronized(lock) {
            if (!forceRefresh) {
                cachedToken?.let { token ->
                    if (!JwtParser.isExpired(token)) return token
                }
            }

            return withFileLock { resolveToken(forceRefresh) }
        }
    }

    private fun resolveToken(forceRefresh: Boolean): String {
        val credentials = CredentialStore.read(serverURL)
        if (credentials != null) {
            if (!forceRefresh && !JwtParser.isExpired(credentials.accessToken)) {
                cachedToken = credentials.accessToken
                return credentials.accessToken
            }

            val refreshToken = credentials.refreshToken
            if (!refreshToken.isNullOrBlank()) {
                try {
                    val newTokens = refreshAuthTokenService.refreshTokens(serverURL, refreshToken)
                    CredentialStore.write(
                        serverURL,
                        Credentials(newTokens.accessToken, newTokens.refreshToken)
                    )
                    cachedToken = newTokens.accessToken
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
                cachedToken = freshCredentials.accessToken
                return freshCredentials.accessToken
            }

            return action()
        } finally {
            fileLock?.release()
            channel.close()
        }
    }
}
