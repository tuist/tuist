package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.services.RefreshAuthTokenService
import java.io.File
import java.net.URI
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption

object JwtUtils {
    fun decodePayload(jwt: String): Map<String, Any>? {
        return try {
            val parts = jwt.split(".")
            if (parts.size != 3) return null
            val payload = parts[1]
            val padded = when (payload.length % 4) {
                2 -> "$payload=="
                3 -> "${payload}="
                else -> payload
            }
            val decoded = java.util.Base64.getUrlDecoder().decode(padded)
            val json = String(decoded, Charsets.UTF_8)
            @Suppress("UNCHECKED_CAST")
            Gson().fromJson(json, Map::class.java) as? Map<String, Any>
        } catch (_: Exception) {
            null
        }
    }

    fun isExpired(jwt: String, bufferSeconds: Int = 30): Boolean {
        val payload = decodePayload(jwt) ?: return true
        val exp = (payload["exp"] as? Number)?.toLong() ?: return true
        val now = System.currentTimeMillis() / 1000
        return now >= (exp - bufferSeconds)
    }

    fun getType(jwt: String): String? {
        val payload = decodePayload(jwt) ?: return null
        return payload["type"] as? String
    }
}

data class TuistCredentials(
    val accessToken: String,
    val refreshToken: String? = null
)

object TuistCredentialStore {
    val credentialsDir: File
        get() = File(System.getProperty("user.home"), ".config/tuist/credentials")

    fun read(serverURL: URI): TuistCredentials? {
        val hostname = serverURL.host ?: return null
        val credFile = File(credentialsDir, "$hostname.json")
        if (!credFile.exists()) return null
        return try {
            Gson().fromJson(credFile.readText(), TuistCredentials::class.java)
        } catch (_: Exception) {
            null
        }
    }

    fun write(serverURL: URI, credentials: TuistCredentials) {
        val hostname = serverURL.host ?: return
        credentialsDir.mkdirs()
        val credFile = File(credentialsDir, "$hostname.json")
        val tempFile = File(credFile.parentFile, "${credFile.name}.tmp")
        try {
            tempFile.writeText(Gson().toJson(credentials))
            tempFile.renameTo(credFile)
        } catch (_: Exception) {
            tempFile.delete()
        }
    }
}

open class TuistTokenProvider(
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
                if (!JwtUtils.isExpired(token)) return token
            }
        }

        synchronized(lock) {
            if (!forceRefresh) {
                cachedToken?.let { token ->
                    if (!JwtUtils.isExpired(token)) return token
                }
            }

            return withFileLock { resolveToken(forceRefresh) }
        }
    }

    private fun resolveToken(forceRefresh: Boolean): String {
        val credentials = TuistCredentialStore.read(serverURL)
        if (credentials != null) {
            if (!forceRefresh && !JwtUtils.isExpired(credentials.accessToken)) {
                cachedToken = credentials.accessToken
                return credentials.accessToken
            }

            val refreshToken = credentials.refreshToken
            if (!refreshToken.isNullOrBlank()) {
                try {
                    val newTokens = refreshAuthTokenService.refreshTokens(serverURL, refreshToken)
                    TuistCredentialStore.write(
                        serverURL,
                        TuistCredentials(newTokens.accessToken, newTokens.refreshToken)
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

            val freshCredentials = TuistCredentialStore.read(serverURL)
            if (freshCredentials != null && !JwtUtils.isExpired(freshCredentials.accessToken)) {
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
