package dev.tuist.gradle

import com.google.gson.Gson
import java.io.File
import java.net.URI

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
