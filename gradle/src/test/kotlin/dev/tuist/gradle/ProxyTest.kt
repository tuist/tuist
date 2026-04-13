package dev.tuist.gradle

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ProxyTest {

    @Test
    fun `None resolves to null`() {
        assertNull(Proxy.None.resolve { null })
        assertNull(Proxy.None.resolveUrl { null })
    }

    @Test
    fun `Url resolves to java-net-Proxy with explicit host and port`() {
        val proxy = Proxy.Url("http://proxy.corp:8080").resolve { null }
        assertNotNull(proxy)
        val address = proxy.address() as java.net.InetSocketAddress
        assertEquals("proxy.corp", address.hostString)
        assertEquals(8080, address.port)
        assertEquals(java.net.Proxy.Type.HTTP, proxy.type())
    }

    @Test
    fun `Url without explicit port uses 80 for http and 443 for https`() {
        val http = Proxy.Url("http://proxy.corp").resolve { null }!!
        assertEquals(80, (http.address() as java.net.InetSocketAddress).port)

        val https = Proxy.Url("https://proxy.corp").resolve { null }!!
        assertEquals(443, (https.address() as java.net.InetSocketAddress).port)
    }

    @Test
    fun `StandardEnvironment reads HTTPS_PROXY first`() {
        val env = mapOf(
            "HTTPS_PROXY" to "http://secure.corp:9443",
            "HTTP_PROXY" to "http://plain.corp:8080"
        )
        val proxy = Proxy.StandardEnvironment.resolve { env[it] }!!
        val address = proxy.address() as java.net.InetSocketAddress
        assertEquals("secure.corp", address.hostString)
        assertEquals(9443, address.port)
    }

    @Test
    fun `StandardEnvironment falls back to HTTP_PROXY when HTTPS_PROXY is unset`() {
        val env = mapOf("HTTP_PROXY" to "http://plain.corp:8080")
        val proxy = Proxy.StandardEnvironment.resolve { env[it] }!!
        val address = proxy.address() as java.net.InetSocketAddress
        assertEquals("plain.corp", address.hostString)
        assertEquals(8080, address.port)
    }

    @Test
    fun `StandardEnvironment honors lowercase variants`() {
        val env = mapOf("https_proxy" to "http://lower.corp:7777")
        val proxy = Proxy.StandardEnvironment.resolve { env[it] }!!
        val address = proxy.address() as java.net.InetSocketAddress
        assertEquals("lower.corp", address.hostString)
        assertEquals(7777, address.port)
    }

    @Test
    fun `StandardEnvironment returns null when no env var is set`() {
        assertNull(Proxy.StandardEnvironment.resolve { null })
    }

    @Test
    fun `EnvironmentVariable reads the custom env var`() {
        val env = mapOf("CORP_PROXY" to "http://custom.corp:6666")
        val proxy = Proxy.EnvironmentVariable("CORP_PROXY").resolve { env[it] }!!
        val address = proxy.address() as java.net.InetSocketAddress
        assertEquals("custom.corp", address.hostString)
        assertEquals(6666, address.port)
    }

    @Test
    fun `EnvironmentVariable returns null when the env var is unset or blank`() {
        assertNull(Proxy.EnvironmentVariable("CORP_PROXY").resolve { null })
        assertNull(Proxy.EnvironmentVariable("CORP_PROXY").resolve { "" })
        assertNull(Proxy.EnvironmentVariable("CORP_PROXY").resolve { "   " })
    }

    @Test
    fun `malformed Url returns null instead of throwing`() {
        assertNull(Proxy.Url("not a url").resolve { null })
    }

    @Test
    fun `resolveUrl round-trips via fromResolvedUrl`() {
        val resolved = Proxy.Url("http://proxy.corp:8080").resolveUrl { null }
        val hydrated = resolveProxyFromParameters(resolved)
        assertTrue(hydrated is Proxy.Url)
        assertEquals("http://proxy.corp:8080", (hydrated as Proxy.Url).value)
    }

    @Test
    fun `fromResolvedUrl maps null or blank to None`() {
        assertEquals(Proxy.None, resolveProxyFromParameters(null))
        assertEquals(Proxy.None, resolveProxyFromParameters(""))
        assertEquals(Proxy.None, resolveProxyFromParameters("   "))
    }
}
