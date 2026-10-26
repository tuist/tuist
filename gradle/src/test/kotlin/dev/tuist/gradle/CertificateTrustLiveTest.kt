package dev.tuist.gradle

import okhttp3.Request
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfSystemProperty
import java.net.URI
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

// Explicit qualification only: ordinary CI must not depend on external test hosts.
@EnabledIfSystemProperty(named = "tuist.trust.live", matches = "true")
class CertificateTrustLiveTest {
    @Test
    fun `actual OkHttp and URL connections reject all twelve public controls and accept unrelated HTTPS`() {
        val clients = TuistHttpClients(useEnvironmentProxy = false)
        val http = clients.okHttp.newBuilder().callTimeout(15, TimeUnit.SECONDS).build()
        for (issuer in listOf("emudhra", "aaa-emudhra")) {
            for (prefix in listOf("dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c")) {
                val url = "https://$prefix-$issuer.we-have-a-problem.com/"
                assertFailsWith<SSLHandshakeException>("OkHttp accepted $url or failed outside TLS") {
                    http.newCall(Request.Builder().url(url).build()).execute().close()
                }
                val connection = clients.openConnection(URI(url), 10_000, 10_000)
                try {
                    assertFailsWith<SSLHandshakeException>("URL connection accepted $url or failed outside TLS") {
                        connection.responseCode
                    }
                } finally {
                    connection.disconnect()
                }
            }
        }
        http.newCall(Request.Builder().url("https://letsencrypt.org/").build()).execute().use {
            assertEquals(200, it.code)
        }
        val connection = clients.openConnection(URI("https://letsencrypt.org/"), 10_000, 10_000)
        try {
            assertEquals(200, connection.responseCode)
        } finally {
            connection.disconnect()
        }
    }
}
