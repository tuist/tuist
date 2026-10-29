package dev.tuist.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import java.net.URI
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.assertTrue

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
    fun `credentials serialize with camelCase field names matching CLI format`() {
        val store = CredentialStore(File(tempDir, "camel"))
        store.write(serverURL, Credentials("access", "refresh"))

        val json = File(File(tempDir, "camel"), "tuist.dev.json").readText()
        assert(json.contains("\"accessToken\""))
        assert(json.contains("\"refreshToken\""))
    }

    @Test
    fun `read handles snake_case credentials from older versions`() {
        val dir = File(tempDir, "legacy")
        dir.mkdirs()
        File(dir, "tuist.dev.json").writeText("""{"access_token":"old-access","refresh_token":"old-refresh"}""")

        val store = CredentialStore(dir)
        val read = store.read(serverURL)
        assertNotNull(read)
        assertEquals("old-access", read.accessToken)
        assertEquals("old-refresh", read.refreshToken)
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

    @Test
    fun `concurrent readers see complete credential pairs during replacement`() {
        val store = CredentialStore(File(tempDir, "concurrent"))
        val old = Credentials("a".repeat(64 * 1024), "old-refresh")
        val new = Credentials("b".repeat(96 * 1024), "new-refresh")
        store.write(serverURL, old)
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(2)
        try {
            val writer = executor.submit {
                start.await()
                repeat(100) { store.write(serverURL, if (it % 2 == 0) new else old) }
            }
            val reader = executor.submit<List<Credentials?>> {
                start.await()
                List(100) { store.read(serverURL) }
            }
            start.countDown()
            val snapshots = reader.get(10, TimeUnit.SECONDS)
            writer.get(10, TimeUnit.SECONDS)
            assertTrue(snapshots.all { it == old || it == new }, "A reader observed partial or missing credentials")
        } finally {
            executor.shutdownNow()
        }
    }
}
