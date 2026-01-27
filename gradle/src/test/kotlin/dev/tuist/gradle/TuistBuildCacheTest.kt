package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class TuistBuildCacheTest {

    @Test
    fun `TuistBuildCache has correct default values`() {
        val cache = TuistBuildCache()

        assertEquals("", cache.fullHandle)
        assertNull(cache.executablePath)
        assertEquals(false, cache.allowInsecureProtocol)
        assertEquals(false, cache.isPush)
    }

    @Test
    fun `TuistBuildCache properties can be configured`() {
        val cache = TuistBuildCache().apply {
            fullHandle = "my-account/my-project"
            executablePath = "/custom/path/tuist"
            allowInsecureProtocol = true
            isPush = true
        }

        assertEquals("my-account/my-project", cache.fullHandle)
        assertEquals("/custom/path/tuist", cache.executablePath)
        assertEquals(true, cache.allowInsecureProtocol)
        assertEquals(true, cache.isPush)
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
    fun `TuistCacheConfiguration handles compact JSON format`() {
        val json = """{"url":"http://localhost:8181","token":"tuist_token","accountHandle":"tuist","projectHandle":"gradle"}"""

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("http://localhost:8181", config.url)
        assertEquals("tuist_token", config.token)
        assertEquals("tuist", config.accountHandle)
        assertEquals("gradle", config.projectHandle)
    }
}
