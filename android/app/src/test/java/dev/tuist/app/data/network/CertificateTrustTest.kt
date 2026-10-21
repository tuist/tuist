package dev.tuist.app.data.network

import android.app.Application
import android.net.http.X509TrustManagerExtensions
import android.os.Build
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.TrustManagerFactory

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 28, 35], application = Application::class)
class CertificateTrustTest {
    @Test
    fun `all twelve public policy keys are rejected`() {
        val certificates = fixtures("issuer-roots.pem") + fixtures("intermediate-controls.pem")
        assertEquals(12, certificates.size)
        assertEquals(CertificateTrust.blockedSPKIHashes, certificates.map(CertificateTrust::spkiHash).toSet())
        for (certificate in certificates) {
            assertThrows(CertificateException::class.java) { CertificateTrust.requireAllowed(listOf(certificate)) }
        }
        CertificateTrust.requireAllowed(fixtures("positive-isrg-root-x1.pem"))
    }

    @Test
    fun `native constructed path is checked not just supplied peers`() {
        val fixture = fixture()
        for (blocked in fixtures("issuer-roots.pem") + fixtures("intermediate-controls.pem")) {
            val original = ReturningNativeManager(fixture.validator, listOf(fixture.leaf, blocked, fixture.root))
            val manager = PolicyTrustManager(original)
            assertThrows(CertificateException::class.java) {
                manager.checkServerTrusted(arrayOf(fixture.leaf), "RSA", "localhost")
            }
            assertEquals("localhost", original.lastHostname)
        }
    }

    @Test
    fun `Android reflection methods preserve native hostname-specific configuration`() {
        val fixture = fixture()
        val original = ReturningNativeManager(fixture.validator, listOf(fixture.leaf, fixture.root))
        val extensions = X509TrustManagerExtensions(PolicyTrustManager(original))
        assertEquals(listOf(fixture.leaf, fixture.root), extensions.checkServerTrusted(arrayOf(fixture.leaf), "RSA", "localhost"))
        assertEquals("localhost", original.lastHostname)
        if (Build.VERSION.SDK_INT >= 28) {
            assertFalse(extensions.isSameTrustConfiguration("first.example", "second.example"))
            assertTrue(extensions.isSameTrustConfiguration("first.example", "first.example"))
        } else {
            assertTrue(PolicyTrustManager(original).isSameTrustConfiguration("first.example", "second.example"))
        }
    }

    @Test
    fun `native failure cannot be converted to success`() {
        val fixture = fixture()
        val original = ReturningNativeManager(fixture.validator, listOf(fixture.leaf, fixture.root))
        original.failure = CertificateException("native policy failure")
        val manager = PolicyTrustManager(original)
        val error = assertThrows(CertificateException::class.java) {
            manager.checkServerTrusted(arrayOf(fixture.leaf), "RSA", "localhost")
        }
        assertEquals("native policy failure", error.message)
    }

    @Test
    fun `actual HTTP and derived clients reject injected leaf and anchor keys`() {
        val fixture = fixture()
        val server = MockWebServer()
        server.useHttps(HandshakeCertificates.Builder().heldCertificate(fixture.heldLeaf).build().sslSocketFactory(), false)
        server.start()
        try {
            for (blocked in listOf(emptySet(), setOf(CertificateTrust.spkiHash(fixture.root)), setOf(CertificateTrust.spkiHash(fixture.leaf)))) {
                val original = ReturningNativeManager(fixture.validator, listOf(fixture.leaf, fixture.root))
                val client = CertificateTrust.clientBuilder(original, blocked).readTimeout(5, TimeUnit.SECONDS)
                    .retryOnConnectionFailure(false).build().newBuilder().build()
                try {
                    val request = Request.Builder().url(server.url("/")).build()
                    if (blocked.isEmpty()) {
                        server.enqueue(MockResponse().setBody("ok"))
                        client.newCall(request).execute().use { assertEquals(200, it.code) }
                    } else {
                        assertThrows(SSLHandshakeException::class.java) { client.newCall(request).execute().close() }
                    }
                    assertNotNull(original.lastSocket)
                    assertEquals("localhost", original.lastHostname)
                } finally {
                    client.connectionPool.evictAll()
                    client.dispatcher.executorService.shutdown()
                }
            }
            assertEquals(1, server.requestCount)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `all socket and engine contexts reach the original validator`() {
        val fixture = fixture()
        val original = ReturningNativeManager(fixture.validator, listOf(fixture.leaf, fixture.root))
        val manager = PolicyTrustManager(original)
        val engine = javax.net.ssl.SSLContext.getDefault().createSSLEngine("localhost", 443)
        manager.checkServerTrusted(arrayOf(fixture.leaf), "RSA", engine)
        assertSame(engine, original.lastEngine)
        val socket = Socket()
        manager.checkServerTrusted(arrayOf(fixture.leaf), "RSA", socket)
        assertSame(socket, original.lastSocket)
    }

    private fun fixtures(name: String): List<X509Certificate> =
        requireNotNull(javaClass.classLoader!!.getResourceAsStream("certificate-trust/$name")).use {
            CertificateFactory.getInstance("X.509").generateCertificates(it).map { certificate -> certificate as X509Certificate }
        }

    private data class Fixture(val root: X509Certificate, val heldLeaf: HeldCertificate, val validator: X509ExtendedTrustManager) {
        val leaf get() = heldLeaf.certificate
    }

    private fun fixture(): Fixture {
        val root = HeldCertificate.Builder().certificateAuthority(1).commonName("Private test CA").build()
        val leaf = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root).build()
        val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            setCertificateEntry("private", root.certificate)
        }
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
        return Fixture(root.certificate, leaf, factory.trustManagers.filterIsInstance<X509ExtendedTrustManager>().single())
    }

    // A JVM validator adapted to Android's public complete-path API. This tests
    // integration, not a claim that Robolectric is a real Conscrypt/device runtime.
    class ReturningNativeManager(private val validator: X509ExtendedTrustManager, private val path: List<X509Certificate>) : X509ExtendedTrustManager() {
        var lastHostname: String? = null
        var lastSocket: Socket? = null
        var lastEngine: SSLEngine? = null
        var failure: CertificateException? = null

        fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, hostname: String?): List<X509Certificate> {
            failure?.let { throw it }
            validator.checkServerTrusted(chain, authType)
            lastHostname = hostname
            return path
        }
        fun isSameTrustConfiguration(first: String, second: String): Boolean = first == second
        override fun getAcceptedIssuers(): Array<X509Certificate> = validator.acceptedIssuers
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) = validator.checkServerTrusted(chain, authType)
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) {
            lastSocket = socket
            validator.checkServerTrusted(chain, authType, socket)
        }
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) {
            lastEngine = engine
            // Unconnected synthetic contexts carry no native session; real socket
            // tests above exercise contextual validation in an actual handshake.
            validator.checkServerTrusted(chain, authType)
        }
        override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) = validator.checkClientTrusted(chain, authType)
        override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) = validator.checkClientTrusted(chain, authType, socket)
        override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) = validator.checkClientTrusted(chain, authType, engine)
    }
}
