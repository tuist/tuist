package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI
import java.util.Locale

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

    fun read(serverURL: URI): Credentials? = read(serverURL, rejectInvalid = false)

    internal fun readValidated(serverURL: URI): Credentials? = read(serverURL, rejectInvalid = true)

    private fun read(serverURL: URI, rejectInvalid: Boolean): Credentials? {
        val hostname = serverURL.host ?: return null
        val credFile = credentialFile(hostname)
        if (!credFile.exists()) return null
        return try {
            val credentials = Gson().fromJson(credFile.readText(), Credentials::class.java)
            if (rejectInvalid && credentials?.accessToken.isNullOrBlank()) {
                throw IllegalArgumentException("Missing access token")
            }
            credentials
        } catch (e: Exception) {
            if (rejectInvalid) {
                throw IllegalStateException("Existing Tuist credentials in $credFile are invalid; re-authenticate with `tuist auth login` or explicitly remove them before publishing.", e)
            }
            logger.warn("Tuist: Credential file {} is corrupt and will be removed. Re-authenticate with `tuist auth login`. Error: {}", credFile, e.message)
            credFile.delete()
            null
        }
    }

    fun write(serverURL: URI, credentials: Credentials) {
        val hostname = serverURL.host ?: return
        credentialsDir.mkdirs()
        credentialFile(hostname).writeText(Gson().toJson(credentials))
    }

    private fun credentialFile(hostname: String): File {
        val normalized = File(credentialsDir, "${hostname.lowercase(Locale.ROOT)}.json")
        if (normalized.exists()) return normalized
        return credentialsDir.listFiles()?.firstOrNull { it.name.equals("$hostname.json", ignoreCase = true) }
            ?: File(credentialsDir, "$hostname.json")
    }

    companion object {
        fun defaultCredentialsDir(): File {
            val baseConfigDir = XdgPaths.configHome()
            return File(File(baseConfigDir, "tuist"), "credentials")
        }
    }
}
