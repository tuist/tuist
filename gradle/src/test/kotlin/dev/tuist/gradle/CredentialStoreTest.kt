package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import java.net.URI

class CredentialStoreTest {

    @TempDir
    lateinit var tempDir: File

    private val serverURL = URI.create("https://tuist.dev")

    @Test
    fun `write and read round-trip`() {
        val store = CredentialStore(File(tempDir, "creds"))
        val creds = Credentials("token-abc", "refresh-xyz")
        store.write(serverURL, creds)

        val read = store.read(serverURL)
        assertNotNull(read)
        assertEquals("token-abc", read.accessToken)
        assertEquals("refresh-xyz", read.refreshToken)
    }

    @Test
    fun `read returns null for missing file`() {
        val store = CredentialStore(File(tempDir, "empty"))
        assertNull(store.read(serverURL))
    }

    @Test
    fun `read returns null and deletes corrupt file`() {
        val dir = File(tempDir, "bad")
        dir.mkdirs()
        File(dir, "tuist.dev.json").writeText("not-json")

        val store = CredentialStore(dir)
        assertNull(store.read(serverURL))
        assertNull(store.read(serverURL))
    }

    @Test
    fun `credentials serialize with snake_case field names`() {
        val store = CredentialStore(File(tempDir, "snake"))
        store.write(serverURL, Credentials("access", "refresh"))

        val json = File(File(tempDir, "snake"), "tuist.dev.json").readText()
        assert(json.contains("\"access_token\""))
        assert(json.contains("\"refresh_token\""))
        assert(!json.contains("\"accessToken\""))
    }

    @Test
    fun `credentials with null refreshToken`() {
        val store = CredentialStore(File(tempDir, "nullrefresh"))
        store.write(serverURL, Credentials("mytoken", null))

        val read = store.read(serverURL)
        assertNotNull(read)
        assertEquals("mytoken", read.accessToken)
        assertNull(read.refreshToken)
    }
}
