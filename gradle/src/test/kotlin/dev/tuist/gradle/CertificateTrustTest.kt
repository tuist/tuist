package dev.tuist.gradle

import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import java.io.IOException
import java.net.Socket
import java.nio.file.Files
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
import javax.net.ssl.SSLHandshakeException
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
        withServer("localhost") { server, chain ->
            val client = client(chain.root)
            Transport.entries.forEach { assertAccepted(client, server, it) }
        }
    }

    @ParameterizedTest
    @CsvSource(
        "OKHTTP,LEAF", "OKHTTP,INTERMEDIATE", "OKHTTP,ROOT", "OKHTTP,ONLY_ROOT",
        "LATENCY,LEAF", "LATENCY,INTERMEDIATE", "LATENCY,ROOT", "LATENCY,ONLY_ROOT",
        "URL_CONNECTION,LEAF", "URL_CONNECTION,INTERMEDIATE", "URL_CONNECTION,ROOT", "URL_CONNECTION,ONLY_ROOT",
    )
    fun `otherwise valid keys are denied on the wire and positives are restored`(transport: Transport, position: Position) {
        withServer("localhost") { server, chain ->
            // The peer sends leaf + intermediate only. The trusted root must be
            // constructed locally, so checking just the peer chain cannot pass.
            assertAccepted(client(chain.root), server, transport)
            val certificate = when (position) {
                Position.LEAF -> chain.leaf
                Position.INTERMEDIATE -> chain.intermediate
                Position.ROOT, Position.ONLY_ROOT -> chain.root
            }.certificate
            val blockedClient = client(
                chain.root,
                setOf(CertificateTrust.spkiHash(certificate)),
                includeUnrelatedAnchor = position != Position.ONLY_ROOT,
            )
            val before = server.requestCount
            assertFailsWith<SSLHandshakeException> { get(blockedClient, server, transport) }
            assertEquals(before, server.requestCount, "TLS rejection must precede HTTP delivery or fallback")
            assertAccepted(client(chain.root), server, transport)
        }
    }

    @Test
    fun `default factories preserve enterprise roots configured through the JVM trust store`() {
        withServer("localhost") { server, chain ->
            val path = Files.createTempFile("tuist-trust", ".p12")
            val properties = listOf("javax.net.ssl.trustStore", "javax.net.ssl.trustStorePassword", "javax.net.ssl.trustStoreType")
            val previous = properties.associateWith(System::getProperty)
            try {
                val store = KeyStore.getInstance("PKCS12").apply {
                    load(null, null)
                    setCertificateEntry("enterprise-root", chain.root.certificate)
                }
                Files.newOutputStream(path).use { store.store(it, "test-only".toCharArray()) }
                System.setProperty(properties[0], path.toString())
                System.setProperty(properties[1], "test-only")
                System.setProperty(properties[2], "PKCS12")
                val client = TuistHttpClients(useEnvironmentProxy = false)
                Transport.entries.forEach { assertAccepted(client, server, it) }
            } finally {
                previous.forEach { (key, value) ->
                    if (value == null) System.clearProperty(key) else System.setProperty(key, value)
                }
                Files.delete(path)
            }
        }
    }

    @Test
    fun `OkHttp and URL connections reject a wrong hostname before sending a request`() {
        withServer("wrong.example.test") { server, chain ->
            val client = client(chain.root)
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
        withServer("localhost", expired = true) { server, chain ->
            assertRejected(client(chain.root), server)
        }
    }

    enum class Transport { OKHTTP, LATENCY, URL_CONNECTION }
    enum class Position { LEAF, INTERMEDIATE, ROOT, ONLY_ROOT }

    private fun assertAccepted(client: TuistHttpClients, server: MockWebServer, transport: Transport) {
        server.enqueue(MockResponse().setBody("ok"))
        assertEquals("ok", get(client, server, transport))
    }

    private fun get(client: TuistHttpClients, server: MockWebServer, transport: Transport): String {
        if (transport != Transport.URL_CONNECTION) {
            val http = if (transport == Transport.OKHTTP) client.okHttp else client.latencyClient
            return http.newCall(Request.Builder().url(server.url("/")).build()).execute().use {
                assertEquals(200, it.code)
                requireNotNull(it.body).string()
            }
        }
        val connection = client.openConnection(server.url("/").toUri())
        try {
            assertEquals(200, connection.responseCode)
            return connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
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

    private fun client(
        root: HeldCertificate,
        additionalBlockedSPKIHashes: Set<String> = emptySet(),
        includeUnrelatedAnchor: Boolean = true,
    ): TuistHttpClients {
        val trust = HandshakeCertificates.Builder().addTrustedCertificate(root.certificate).apply {
            if (includeUnrelatedAnchor) addTrustedCertificate(certificates("positive-isrg-root-x1").single())
        }.build().trustManager
        return TuistHttpClients(
            useEnvironmentProxy = false,
            trustManagerProvider = { trust },
            additionalBlockedSPKIHashes = additionalBlockedSPKIHashes,
        )
    }

    private data class Chain(val root: HeldCertificate, val intermediate: HeldCertificate, val leaf: HeldCertificate)

    private fun withServer(hostname: String, expired: Boolean = false, action: (MockWebServer, Chain) -> Unit) {
        val root = HeldCertificate.Builder().certificateAuthority(1).build()
        val intermediate = HeldCertificate.Builder().certificateAuthority(0).signedBy(root).build()
        val builder = HeldCertificate.Builder().addSubjectAlternativeName(hostname).signedBy(intermediate)
        if (expired) builder.validityInterval(1_000, 2_000)
        val leaf = builder.build()
        val certificate = HandshakeCertificates.Builder().heldCertificate(leaf, intermediate.certificate).build()
        MockWebServer().use { server ->
            server.useHttps(certificate.sslSocketFactory(), false)
            server.start()
            action(server, Chain(root, intermediate, leaf))
        }
    }

    private fun certificates(name: String): List<X509Certificate> =
        requireNotNull(javaClass.getResourceAsStream("/certificate-trust/$name.pem")).use { stream ->
            CertificateFactory.getInstance("X.509").generateCertificates(stream).map { it as X509Certificate }
        }
}
