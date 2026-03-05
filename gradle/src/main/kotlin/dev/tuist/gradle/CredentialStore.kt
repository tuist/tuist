package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI

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
        val hostname = serverURL.host ?: return null
        val credFile = File(credentialsDir, "$hostname.json")
        if (!credFile.exists()) return null
        return try {
            Gson().fromJson(credFile.readText(), Credentials::class.java)
        } catch (e: Exception) {
            logger.warn("Tuist: Credential file {} is corrupt and will be removed. Re-authenticate with `tuist auth login`. Error: {}", credFile, e.message)
            credFile.delete()
            null
        }
    }

    fun write(serverURL: URI, credentials: Credentials) {
        val hostname = serverURL.host ?: return
        credentialsDir.mkdirs()
        File(credentialsDir, "$hostname.json").writeText(Gson().toJson(credentials))
    }

    companion object {
        fun defaultCredentialsDir(): File {
            val baseConfigDir = XdgPaths.configHome()
            return File(File(baseConfigDir, "tuist"), "credentials")
        }
    }
}
