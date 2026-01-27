package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class TuistBuildCacheTest {

    @TempDir
    lateinit var tempDir: File

    @Test
    fun `TuistBuildCache has correct default values`() {
        val cache = TuistBuildCache()

        assertEquals("", cache.fullHandle)
        assertNull(cache.executablePath)
        assertEquals(false, cache.allowInsecureProtocol)
        // isPush defaults to false in AbstractBuildCache
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `TuistBuildCache properties can be configured`() {
        val cache = TuistBuildCache().apply {
            fullHandle = "my-account/my-project"
            executablePath = "/custom/path/tuist"
            allowInsecureProtocol = true
            isPush = false
        }

        assertEquals("my-account/my-project", cache.fullHandle)
        assertEquals("/custom/path/tuist", cache.executablePath)
        assertEquals(true, cache.allowInsecureProtocol)
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `findTuistInPath returns path when executable exists`() {
        val binDir = File(tempDir, "bin")
        binDir.mkdirs()
        val tuistFile = File(binDir, "tuist")
        tuistFile.writeText("#!/bin/bash\necho 'tuist'")
        tuistFile.setExecutable(true)

        val result = findTuistInPathWithCustomPath(binDir.absolutePath)

        assertNotNull(result)
        assertEquals(tuistFile.absolutePath, result)
    }

    @Test
    fun `findTuistInPath returns null when executable does not exist`() {
        val emptyDir = File(tempDir, "empty")
        emptyDir.mkdirs()

        val result = findTuistInPathWithCustomPath(emptyDir.absolutePath)

        assertNull(result)
    }

    @Test
    fun `findTuistInPath returns null when file exists but is not executable`() {
        val binDir = File(tempDir, "bin")
        binDir.mkdirs()
        val tuistFile = File(binDir, "tuist")
        tuistFile.writeText("not executable")
        tuistFile.setExecutable(false)

        val result = findTuistInPathWithCustomPath(binDir.absolutePath)

        assertNull(result)
    }

    @Test
    fun `findTuistInPath searches multiple directories in order`() {
        val firstDir = File(tempDir, "first")
        val secondDir = File(tempDir, "second")
        firstDir.mkdirs()
        secondDir.mkdirs()

        val tuistInSecond = File(secondDir, "tuist")
        tuistInSecond.writeText("#!/bin/bash\necho 'tuist'")
        tuistInSecond.setExecutable(true)

        val pathSeparator = System.getProperty("path.separator") ?: ":"
        val result = findTuistInPathWithCustomPath(
            "${firstDir.absolutePath}${pathSeparator}${secondDir.absolutePath}"
        )

        assertNotNull(result)
        assertEquals(tuistInSecond.absolutePath, result)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with simple base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://cache.tuist.dev",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )

        val result = buildCacheUrl(config, "abc123def456")

        assertEquals("https", result.scheme)
        assertEquals("cache.tuist.dev", result.host)
        assertEquals("/api/cache/gradle/abc123def456", result.path)
        assertEquals("account_handle=my-account&project_handle=my-project", result.query)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with trailing slash in base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://cache.tuist.dev/",
            token = "test-token",
            accountHandle = "my-account",
            projectHandle = "my-project"
        )

        val result = buildCacheUrl(config, "abc123")

        assertEquals("/api/cache/gradle/abc123", result.path)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with port`() {
        val config = TuistCacheConfiguration(
            url = "http://localhost:8181",
            token = "test-token",
            accountHandle = "tuist",
            projectHandle = "gradle"
        )

        val result = buildCacheUrl(config, "hash123")

        assertEquals("http", result.scheme)
        assertEquals("localhost", result.host)
        assertEquals(8181, result.port)
        assertEquals("/api/cache/gradle/hash123", result.path)
        assertEquals("account_handle=tuist&project_handle=gradle", result.query)
    }

    @Test
    fun `buildCacheUrl constructs correct URL with existing path in base URL`() {
        val config = TuistCacheConfiguration(
            url = "https://api.example.com/v1",
            token = "test-token",
            accountHandle = "org",
            projectHandle = "repo"
        )

        val result = buildCacheUrl(config, "cachekey")

        assertEquals("/v1/api/cache/gradle/cachekey", result.path)
    }

    @Test
    fun `TuistCacheConfiguration parses JSON correctly`() {
        val json = """
            {
                "url": "https://cache.tuist.dev",
                "token": "tuist_test_token_12345",
                "accountHandle": "my-account",
                "projectHandle": "my-project"
            }
        """.trimIndent()

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("https://cache.tuist.dev", config.url)
        assertEquals("tuist_test_token_12345", config.token)
        assertEquals("my-account", config.accountHandle)
        assertEquals("my-project", config.projectHandle)
    }

    @Test
    fun `TuistCacheConfiguration handles empty values in JSON`() {
        val json = """
            {
                "url": "",
                "token": "",
                "accountHandle": "",
                "projectHandle": ""
            }
        """.trimIndent()

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("", config.url)
        assertEquals("", config.token)
        assertEquals("", config.accountHandle)
        assertEquals("", config.projectHandle)
    }

    @Test
    fun `TuistCacheConfiguration handles real-world JSON format`() {
        val json = """{"url":"http://localhost:8181","token":"tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken","accountHandle":"tuist","projectHandle":"gradle"}"""

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("http://localhost:8181", config.url)
        assertEquals("tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken", config.token)
        assertEquals("tuist", config.accountHandle)
        assertEquals("gradle", config.projectHandle)
    }

    private fun findTuistInPathWithCustomPath(customPath: String): String? {
        val pathSeparator = System.getProperty("path.separator") ?: ":"
        val executableName = if (System.getProperty("os.name").lowercase().contains("win")) "tuist.exe" else "tuist"

        for (dir in customPath.split(pathSeparator)) {
            val file = File(dir, executableName)
            if (file.exists() && file.canExecute()) {
                return file.absolutePath
            }
        }
        return null
    }

    private fun buildCacheUrl(config: TuistCacheConfiguration, cacheKey: String): URI {
        val baseUri = URI.create(config.url.trimEnd('/'))
        return URI(
            baseUri.scheme,
            baseUri.userInfo,
            baseUri.host,
            baseUri.port,
            "${baseUri.path}/api/cache/gradle/$cacheKey",
            "account_handle=${config.accountHandle}&project_handle=${config.projectHandle}",
            null
        )
    }
}
