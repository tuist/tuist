package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.nio.file.StandardCopyOption

data class Credentials(
    @SerializedName(value = "accessToken", alternate = ["access_token"])
    val accessToken: String,
    @SerializedName(value = "refreshToken", alternate = ["refresh_token"])
    val refreshToken: String? = null
)

class CredentialStore(
    private val credentialsDir: File = defaultCredentialsDir()
) {
    private val logger = LoggerFactory.getLogger(CredentialStore::class.java)

    fun read(serverURL: URI): Credentials? {
        val credFile = credentialsFile(serverURL) ?: return null
        if (!credFile.exists()) return null
        return try {
            Gson().fromJson(Files.readString(credFile.toPath()), Credentials::class.java)
        } catch (e: Exception) {
            logger.warn("Tuist: Credential file {} is corrupt and will be removed. Re-authenticate with `tuist auth login`. Error: {}", credFile, e.message)
            credFile.delete()
            null
        }
    }

    fun write(serverURL: URI, credentials: Credentials) {
        val credFile = credentialsFile(serverURL) ?: return
        credentialsDir.mkdirs()
        val temporaryFile = Files.createTempFile(credentialsDir.toPath(), ".credentials-", ".json")
        try {
            Files.writeString(temporaryFile, Gson().toJson(credentials))
            Files.move(temporaryFile, credFile.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } finally {
            Files.deleteIfExists(temporaryFile)
        }
    }

    internal fun refreshLockFile(serverURL: URI): File {
        val storageKey = credentialsFile(serverURL)?.toPath()?.toAbsolutePath()?.normalize()?.toString()
            ?: serverURL.toString()
        // Match the Swift client's credential-refresh key and flock, including URL aliases sharing the same file.
        var hash = 14695981039346656037uL
        for (byte in storageKey.toByteArray(Charsets.UTF_8)) {
            hash = (hash xor byte.toUByte().toULong()) * 1099511628211uL
        }
        return File(XdgPaths.stateHome(), "tuist/cached_value_store/credential-refresh-${hash.toString(16)}.lock")
    }

    private fun credentialsFile(serverURL: URI): File? =
        serverURL.host?.let { File(credentialsDir, "$it.json") }

    companion object {
        fun defaultCredentialsDir(): File {
            val baseConfigDir = XdgPaths.configHome()
            return File(File(baseConfigDir, "tuist"), "credentials")
        }
    }
}
