package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.slf4j.LoggerFactory
import java.io.File
import java.net.URI
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes
import java.util.Locale

data class Credentials(
    @SerializedName(value = "accessToken", alternate = ["access_token"])
    val accessToken: String,
    @SerializedName(value = "refreshToken", alternate = ["refresh_token"])
    val refreshToken: String? = null,
    val rejected: Boolean? = null
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
        if (!exists(credFile)) return null
        return try {
            val credentials = Gson().fromJson(credFile.readText(), Credentials::class.java)
            if (rejectInvalid && (credentials?.accessToken.isNullOrBlank() || credentials?.rejected == true)) {
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
        val host = hostname.lowercase(Locale.ROOT).trimEnd('.')
        val normalized = File(credentialsDir, "$host.json")
        try {
            val directory = credentialsDir.toPath().toAbsolutePath()
            var ancestor = directory.root
            for (component in directory) {
                ancestor = ancestor.resolve(component)
                val attributes = try {
                    Files.readAttributes(ancestor, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
                } catch (_: NoSuchFileException) {
                    return normalized
                }
                val target = if (attributes.isSymbolicLink) {
                    Files.readAttributes(ancestor, BasicFileAttributes::class.java)
                } else attributes
                check(target.isDirectory) { "Tuist credentials ancestor $ancestor is not a directory" }
            }
            if (exists(normalized)) return normalized
            return Files.newDirectoryStream(directory).use { files ->
                files.map { it.toFile() }.sortedBy { it.name }.firstOrNull {
                    it.name.endsWith(".json") && it.name.removeSuffix(".json").lowercase(Locale.ROOT).trimEnd('.') == host
                } ?: normalized
            }
        } catch (e: Exception) {
            throw IllegalStateException("Could not inspect existing Tuist credentials in $credentialsDir; fix directory access before publishing.", e)
        }
    }

    private fun exists(file: File): Boolean = try {
        Files.readAttributes(file.toPath(), BasicFileAttributes::class.java, NOFOLLOW_LINKS)
        true
    } catch (_: NoSuchFileException) {
        false
    } catch (e: Exception) {
        throw IllegalStateException("Could not inspect Tuist credentials in $file; fix directory access before publishing.", e)
    }

    companion object {
        fun defaultCredentialsDir(): File {
            val baseConfigDir = XdgPaths.configHome()
            return File(File(baseConfigDir, "tuist"), "credentials")
        }
    }
}
