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

class CredentialStoreTest {

    @TempDir
    lateinit var tempDir: File

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
    fun `credentials serialize with camelCase field names`() {
        val credentials = Credentials("access", "refresh")
        val json = Gson().toJson(credentials)
        assertTrue(json.contains("\"accessToken\""))
        assertTrue(json.contains("\"refreshToken\""))
        assertFalse(json.contains("\"access_token\""))
        assertFalse(json.contains("\"refresh_token\""))
    }

    @Test
    fun `credentials deserialize from camelCase JSON`() {
        val json = """{"accessToken":"mytoken","refreshToken":"myrefresh"}"""
        val creds = Gson().fromJson(json, Credentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertEquals("myrefresh", creds.refreshToken)
    }

    @Test
    fun `credentials with null refreshToken`() {
        val json = """{"accessToken":"mytoken"}"""
        val creds = Gson().fromJson(json, Credentials::class.java)
        assertEquals("mytoken", creds.accessToken)
        assertNull(creds.refreshToken)
    }
}
