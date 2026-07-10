package dev.tuist.app.data

import android.content.Context
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class EnvironmentConfigTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        clearPreferences()
    }

    @After
    fun tearDown() {
        clearPreferences()
    }

    @Test
    fun `uses production server by default`() {
        val subject = EnvironmentConfig(context)

        assertEquals("https://tuist.dev", subject.serverUrl)
        assertNull(subject.customServerUrl)
    }

    @Test
    fun `persists normalized custom server and resets it`() {
        val subject = EnvironmentConfig(context)

        subject.setCustomServerUrl("  EXAMPLE.com:443/  ")

        assertEquals("https://example.com", subject.serverUrl)
        assertEquals("https://example.com", EnvironmentConfig(context).customServerUrl)

        EnvironmentConfig(context).resetServerUrl()

        assertEquals("https://tuist.dev", subject.serverUrl)
        assertNull(subject.customServerUrl)
    }

    @Test
    fun `custom server takes precedence over selected debug environment`() {
        val subject = EnvironmentConfig(context)
        subject.setEnvironment(TuistEnvironment.STAGING)

        subject.setCustomServerUrl("https://example.com")

        assertEquals("https://example.com", subject.serverUrl)
        assertEquals(TuistEnvironment.STAGING, subject.current)
    }

    @Test
    fun `selecting named environment clears custom server`() {
        val subject = EnvironmentConfig(context)
        subject.setCustomServerUrl("https://example.com")

        val changed = subject.setEnvironment(TuistEnvironment.CANARY)

        assertTrue(changed)
        assertNull(subject.customServerUrl)
        assertEquals("https://canary.tuist.dev", subject.serverUrl)
        assertFalse(subject.setEnvironment(TuistEnvironment.CANARY))
    }

    @Test
    fun `normalizes secure server addresses`() {
        val addresses = mapOf(
            "example.com" to "https://example.com",
            "HTTPS://EXAMPLE.COM" to "https://example.com",
            "https://example.com/" to "https://example.com",
            "https://example.com:443" to "https://example.com",
            "https://example.com:8443" to "https://example.com:8443",
        )

        addresses.forEach { (input, expected) ->
            assertEquals(expected, EnvironmentConfig.normalizeServerUrl(input))
        }
    }

    @Test
    fun `allows cleartext loopback servers`() {
        val addresses = mapOf(
            "http://localhost:8080" to "http://localhost:8080",
            "http://LOCALHOST:80/" to "http://localhost",
            "http://127.0.0.1:8080" to "http://127.0.0.1:8080",
            "http://127.255.255.255" to "http://127.255.255.255",
            "http://[::1]:8080" to "http://[::1]:8080",
        )

        addresses.forEach { (input, expected) ->
            assertEquals(expected, EnvironmentConfig.normalizeServerUrl(input))
        }
    }

    @Test
    fun `rejects invalid server addresses`() {
        val addresses = listOf(
            "",
            "http://example.com",
            "http://127.0.0.1.example.com",
            "ftp://example.com",
            "https://example.com/path",
            "https://example.com?query=value",
            "https://example.com#fragment",
            "https://user:password@example.com",
            "https://example.com:99999",
            "not a host",
        )

        addresses.forEach { input ->
            assertThrows(IllegalArgumentException::class.java) {
                EnvironmentConfig.normalizeServerUrl(input)
            }
        }
    }

    private fun clearPreferences() {
        context.getSharedPreferences("tuist_environment", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }
}
