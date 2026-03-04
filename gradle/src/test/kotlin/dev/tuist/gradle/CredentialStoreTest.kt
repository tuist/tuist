package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import java.net.URI

class CredentialStoreTest {

    @TempDir
    lateinit var tempDir: File

    private val serverURL = URI.create("https://tuist.dev")

    @org.junit.jupiter.api.AfterEach
    fun tearDown() {
        CredentialStore.credentialsDirOverride = null
    }

    @Test
    fun `write and read round-trip via CredentialStore`() {
        CredentialStore.credentialsDirOverride = File(tempDir, "creds")
        val creds = Credentials("token-abc", "refresh-xyz")
        CredentialStore.write(serverURL, creds)

        val read = CredentialStore.read(serverURL)
        assertNotNull(read)
        assertEquals("token-abc", read.accessToken)
        assertEquals("refresh-xyz", read.refreshToken)
    }

    @Test
    fun `read returns null for missing file`() {
        CredentialStore.credentialsDirOverride = File(tempDir, "empty")
        assertNull(CredentialStore.read(serverURL))
    }

    @Test
    fun `read returns null for malformed JSON`() {
        CredentialStore.credentialsDirOverride = File(tempDir, "bad")
        File(tempDir, "bad").mkdirs()
        File(File(tempDir, "bad"), "tuist.dev.json").writeText("not-json")
        assertNull(CredentialStore.read(serverURL))
    }

    @Test
    fun `write creates parent directories`() {
        val nestedDir = File(tempDir, "a/b/c")
        CredentialStore.credentialsDirOverride = nestedDir
        CredentialStore.write(serverURL, Credentials("tok", null))

        assertTrue(nestedDir.exists())
        assertNotNull(CredentialStore.read(serverURL))
    }

    @Test
    fun `write and read credentials round-trip`() {
        val credDir = File(tempDir, "credentials")
        credDir.mkdirs()

        val hostname = "tuist.dev"
        val credFile = File(credDir, "$hostname.json")
        val credentials = Credentials("access-token-123", "refresh-token-456")
        credFile.writeText(Gson().toJson(credentials))

        val read = Gson().fromJson(credFile.readText(), Credentials::class.java)

        assertNotNull(read)
        assertEquals("access-token-123", read.accessToken)
        assertEquals("refresh-token-456", read.refreshToken)
    }

    @Test
    fun `credentials serialize with snake_case field names`() {
        val credentials = Credentials("access", "refresh")
        val json = Gson().toJson(credentials)
        assertTrue(json.contains("\"access_token\""))
        assertTrue(json.contains("\"refresh_token\""))
        assertFalse(json.contains("\"accessToken\""))
        assertFalse(json.contains("\"refreshToken\""))
    }

    @Test
    fun `credentials deserialize from snake_case JSON`() {
        val json = """{"access_token":"mytoken","refresh_token":"myrefresh"}"""
        val creds = Gson().fromJson(json, Credentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertEquals("myrefresh", creds.refreshToken)
    }

    @Test
    fun `credentials with null refreshToken`() {
        val json = """{"access_token":"mytoken"}"""
        val creds = Gson().fromJson(json, Credentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertNull(creds.refreshToken)
    }
}
