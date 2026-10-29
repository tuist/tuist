package dev.tuist.app.data.network

import android.app.Application
import android.graphics.Bitmap
import android.net.http.X509TrustManagerExtensions
import android.os.Build
import coil3.request.CachePolicy
import coil3.request.ErrorResult
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import dev.tuist.app.TuistApplication
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkObject
import io.mockk.unmockkObject
import kotlinx.coroutines.runBlocking
import okhttp3.Request
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import okio.Buffer
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLPeerUnverifiedException
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
    fun `production API and Coil clients deny otherwise accepted leaf intermediate and absent root`() = runBlocking {
        val root = HeldCertificate.Builder().certificateAuthority(2).commonName("Enterprise root").build()
        val intermediate = HeldCertificate.Builder().certificateAuthority(1).commonName("Enterprise intermediate").signedBy(root).build()
        val leaf = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(intermediate).build()
        val path = listOf(leaf.certificate, intermediate.certificate, root.certificate)
        val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            setCertificateEntry("enterprise", root.certificate)
        }
        val validator = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
            .trustManagers.filterIsInstance<X509ExtendedTrustManager>().single()
        val original = ReturningNativeManager(validator, path)
        val server = MockWebServer().apply {
            useHttps(HandshakeCertificates.Builder().heldCertificate(leaf, intermediate.certificate).build().sslSocketFactory(), false)
            start()
        }
        val png = ByteArrayOutputStream().use { output ->
            Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, output)
            output.toByteArray()
        }
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse =
                if (request.path!!.endsWith(".png")) MockResponse().setHeader("Content-Type", "image/png").setBody(Buffer().write(png))
                else MockResponse().setBody("ok")
        }
        val tokens = mockk<TokenStorage> { every { getAccessToken() } returns "test-only-token" }
        try {
            // Substitute only trust inputs; keep the policy, production client factories, TLS and Coil fetch real.
            for (deny in listOf(emptySet<String>()) + path.map { setOf(CertificateTrust.spkiHash(it)) } + listOf(emptySet())) {
                val policyClient = CertificateTrust.clientBuilder(original, deny).readTimeout(5, TimeUnit.SECONDS)
                    .retryOnConnectionFailure(false).build()
                mockkObject(CertificateTrust)
                every { CertificateTrust.clientBuilder(any(), any()) } answers { policyClient.newBuilder() }
                val plain = NetworkModule.providePlainOkHttpClient()
                val api = NetworkModule.provideOkHttpClient(RequestIdInterceptor(), AuthInterceptor(tokens), mockk())
                val loader = TuistApplication().newImageLoader(RuntimeEnvironment.getApplication())
                try {
                    for (client in listOf(plain, api)) {
                        val request = Request.Builder().url(server.url("/api")).build()
                        if (deny.isEmpty()) {
                            client.newCall(request).execute().use { assertEquals("ok", it.body!!.string()) }
                            val received = server.takeRequest(5, TimeUnit.SECONDS)!!
                            assertEquals(if (client === api) "Bearer test-only-token" else null, received.getHeader("Authorization"))
                            val wrongHost = request.newBuilder().url(server.url("/api").newBuilder().host("127.0.0.1").build()).build()
                            assertThrows(SSLPeerUnverifiedException::class.java) { client.newCall(wrongHost).execute().close() }
                        } else {
                            val error = assertThrows(SSLHandshakeException::class.java) { client.newCall(request).execute().close() }
                            assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it.message?.contains("distrusted public key") == true })
                        }
                    }
                    val imageRequest = ImageRequest.Builder(RuntimeEnvironment.getApplication())
                        .memoryCachePolicy(CachePolicy.DISABLED).diskCachePolicy(CachePolicy.DISABLED)
                        .data(server.url("/image-${deny.hashCode()}.png").toString()).build()
                    val image = loader.execute(imageRequest)
                    if (deny.isEmpty()) {
                        assertTrue(image.toString(), image is SuccessResult)
                        assertNull(server.takeRequest(5, TimeUnit.SECONDS)!!.getHeader("Authorization"))
                    } else {
                        assertTrue(image.toString(), image is ErrorResult)
                        assertTrue(generateSequence((image as ErrorResult).throwable as Throwable?) { it.cause }
                            .any { it.message?.contains("distrusted public key") == true })
                    }
                } finally {
                    loader.shutdown()
                    plain.connectionPool.evictAll()
                    policyClient.dispatcher.executorService.shutdown()
                    unmockkObject(CertificateTrust)
                }
            }
            assertEquals(6, server.requestCount)
        } finally {
            unmockkObject(CertificateTrust)
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
