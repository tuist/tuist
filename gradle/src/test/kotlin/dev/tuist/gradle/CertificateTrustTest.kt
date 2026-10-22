package dev.tuist.gradle

import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.jupiter.api.Test
import java.io.IOException
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.CertPathValidator
import java.security.cert.CertPathValidatorException
import java.security.cert.PKIXParameters
import java.security.cert.TrustAnchor
import java.security.cert.X509Certificate
import java.util.Date
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedTrustManager
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class CertificateTrustTest {
    @Test
    fun `rejects all twelve actual keys including intermediates`() {
        val certificates = certificates("issuer-roots") + certificates("distrusted-intermediates")
        assertEquals(12, certificates.size)
        assertEquals(CertificateTrust.blockedSPKIHashes, certificates.map(CertificateTrust::spkiHash).toSet())
        certificates.forEach { certificate ->
            assertFailsWith<CertificateException> { CertificateTrust.requireAllowed(arrayOf(certificate)) }
        }
        CertificateTrust.requireAllowed((certificates("positive-isrg-root-x1") + certificates("positive-isrg-r11")).toTypedArray())
    }

    @Test
    fun `PKIX checker rejects real intermediate keys in constructed certificate paths`() {
        val anchors = certificates("issuer-roots").map { TrustAnchor(it, null) }.toSet()
        val factory = CertificateFactory.getInstance("X.509")
        val validator = CertPathValidator.getInstance("PKIX")
        for (certificate in certificates("distrusted-intermediates")) {
            val path = factory.generateCertPath(listOf(certificate))
            val parameters = PKIXParameters(anchors).apply {
                // Offline signature/path baseline at the public fixture's validity time.
                isRevocationEnabled = false
                date = Date(certificate.notBefore.time + 60_000)
            }
            validator.validate(path, parameters)
            parameters.addCertPathChecker(CertificateTrust.DistrustedKeyChecker())
            val error = assertFailsWith<CertPathValidatorException> { validator.validate(path, parameters) }
            assertTrue(error.message.orEmpty().contains("distrusted public key"))
        }
    }

    @Test
    fun `filters implicit and additional anchors without mutating the original trust store`() {
        val blocked = certificates("issuer-roots") + certificates("distrusted-intermediates")
        val positive = certificates("positive-isrg-root-x1")
        val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            (blocked + positive).forEachIndexed { index, certificate -> setCertificateEntry("anchor-$index", certificate) }
        }
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
        val original = factory.trustManagers.filterIsInstance<javax.net.ssl.X509TrustManager>().single()
        val before = original.acceptedIssuers.map(CertificateTrust::spkiHash).toSet()
        val filtered = CertificateTrust.create(original).trustManager
        assertEquals(positive.map(CertificateTrust::spkiHash).toSet(), filtered.acceptedIssuers.map(CertificateTrust::spkiHash).toSet())
        assertEquals(before, original.acceptedIssuers.map(CertificateTrust::spkiHash).toSet())
    }

    @Test
    fun `all six verification methods preserve the original validator and context`() {
        val positive = certificates("positive-isrg-root-x1").toTypedArray()
        val socket = Socket()
        val engine = SSLContext.getDefault().createSSLEngine()
        val original = object : X509ExtendedTrustManager() {
            override fun getAcceptedIssuers() = positive
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = fail("server")
            override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = fail("client")
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, actual: Socket) {
                assertTrue(actual === socket)
                fail("server-socket")
            }
            override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, actual: Socket) {
                assertTrue(actual === socket)
                fail("client-socket")
            }
            override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, actual: SSLEngine) {
                assertTrue(actual === engine)
                fail("server-engine")
            }
            override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, actual: SSLEngine) {
                assertTrue(actual === engine)
                fail("client-engine")
            }
            private fun fail(method: String): Nothing = throw CertificateException(method)
        }
        val manager = CertificateTrust.create(original).trustManager as X509ExtendedTrustManager
        val calls = listOf<Pair<String, () -> Unit>>(
            "server" to { manager.checkServerTrusted(positive, "RSA") },
            "client" to { manager.checkClientTrusted(positive, "RSA") },
            "server-socket" to { manager.checkServerTrusted(positive, "RSA", socket) },
            "client-socket" to { manager.checkClientTrusted(positive, "RSA", socket) },
            "server-engine" to { manager.checkServerTrusted(positive, "RSA", engine) },
            "client-engine" to { manager.checkClientTrusted(positive, "RSA", engine) },
        )
        calls.forEach { (method, call) ->
            assertEquals(method, assertFailsWith<CertificateException> { call() }.message)
        }
        socket.close()
    }

    @Test
    fun `OkHttp URL connections and derived latency client retain private CA support`() {
        withServer("localhost") { server, root ->
            val client = client(root)
            for (http in listOf(client.okHttp, client.latencyClient)) {
                server.enqueue(MockResponse().setBody("ok"))
                http.newCall(Request.Builder().url(server.url("/")).build()).execute().use {
                    assertEquals(200, it.code)
                    assertEquals("ok", it.body?.string())
                }
            }
            server.enqueue(MockResponse().setBody("ok"))
            val connection = client.openConnection(server.url("/").toUri())
            try {
                assertEquals(200, connection.responseCode)
                assertEquals("ok", connection.inputStream.bufferedReader().use { it.readText() })
            } finally {
                connection.disconnect()
            }
        }
    }

    @Test
    fun `OkHttp and URL connections reject a wrong hostname before sending a request`() {
        withServer("wrong.example.test") { server, root ->
            val client = client(root)
            assertRejected(client, server)
        }
    }

    @Test
    fun `OkHttp and URL connections reject an unrelated CA before sending a request`() {
        withServer("localhost") { server, _ ->
            val unrelated = HeldCertificate.Builder().certificateAuthority(0).build()
            assertRejected(client(unrelated), server)
        }
    }

    @Test
    fun `OkHttp and URL connections reject an expired certificate before sending a request`() {
        withServer("localhost", expired = true) { server, root ->
            assertRejected(client(root), server)
        }
    }

    private fun assertRejected(client: TuistHttpClients, server: MockWebServer) {
        assertFailsWith<IOException> {
            client.okHttp.newCall(Request.Builder().url(server.url("/")).build()).execute().close()
        }
        val connection = client.openConnection(server.url("/").toUri())
        try {
            assertFailsWith<IOException> { connection.responseCode }
        } finally {
            connection.disconnect()
        }
        assertEquals(0, server.requestCount)
    }

    private fun client(root: HeldCertificate): TuistHttpClients {
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(root.certificate).build().trustManager
        return TuistHttpClients(useEnvironmentProxy = false, trustManagerProvider = { trust })
    }

    private fun withServer(hostname: String, expired: Boolean = false, action: (MockWebServer, HeldCertificate) -> Unit) {
        val root = HeldCertificate.Builder().certificateAuthority(0).build()
        val builder = HeldCertificate.Builder().addSubjectAlternativeName(hostname).signedBy(root)
        if (expired) builder.validityInterval(1_000, 2_000)
        val leaf = builder.build()
        val certificate = HandshakeCertificates.Builder().heldCertificate(leaf, root.certificate).build()
        MockWebServer().use { server ->
            server.useHttps(certificate.sslSocketFactory(), false)
            server.start()
            action(server, root)
        }
    }

    private fun certificates(name: String): List<X509Certificate> =
        requireNotNull(javaClass.getResourceAsStream("/certificate-trust/$name.pem")).use { stream ->
            CertificateFactory.getInstance("X.509").generateCertificates(stream).map { it as X509Certificate }
        }
}
