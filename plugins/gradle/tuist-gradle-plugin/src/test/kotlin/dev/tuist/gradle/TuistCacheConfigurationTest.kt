package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class TuistCacheConfigurationTest {

    @Test
    fun `parses JSON configuration correctly`() {
        val json = """
            {
                "endpoint": "https://cache.tuist.dev/api/cache/gradle",
                "token": "tuist_test_token_12345",
                "accountHandle": "my-account",
                "projectHandle": "my-project"
            }
        """.trimIndent()

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("https://cache.tuist.dev/api/cache/gradle", config.endpoint)
        assertEquals("tuist_test_token_12345", config.token)
        assertEquals("my-account", config.accountHandle)
        assertEquals("my-project", config.projectHandle)
    }

    @Test
    fun `handles empty values in JSON`() {
        val json = """
            {
                "endpoint": "",
                "token": "",
                "accountHandle": "",
                "projectHandle": ""
            }
        """.trimIndent()

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("", config.endpoint)
        assertEquals("", config.token)
        assertEquals("", config.accountHandle)
        assertEquals("", config.projectHandle)
    }

    @Test
    fun `handles real-world JSON format`() {
        val json = """{"endpoint":"http://localhost:8181/api/cache/gradle","token":"tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken","accountHandle":"tuist","projectHandle":"gradle"}"""

        val config = Gson().fromJson(json, TuistCacheConfiguration::class.java)

        assertEquals("http://localhost:8181/api/cache/gradle", config.endpoint)
        assertEquals("tuist_01234567-89ab-cdef-0123-456789abcdef_gradlecachedevtoken", config.token)
        assertEquals("tuist", config.accountHandle)
        assertEquals("gradle", config.projectHandle)
    }
}
