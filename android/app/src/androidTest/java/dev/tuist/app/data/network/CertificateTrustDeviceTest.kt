package dev.tuist.app.data.network

import android.net.http.X509TrustManagerExtensions
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

@RunWith(AndroidJUnit4::class)
class CertificateTrustDeviceTest {
    @Test
    fun actualNativeProviderHashesAllTwelvePolicyKeys() {
        val certificates = fixtures("issuer-roots.pem") + fixtures("intermediate-controls.pem")
        assertEquals(12, certificates.size)
        assertEquals(CertificateTrust.blockedSPKIHashes, certificates.map(CertificateTrust::spkiHash).toSet())
        certificates.forEach { certificate ->
            assertThrows(java.security.cert.CertificateException::class.java) { CertificateTrust.requireAllowed(listOf(certificate)) }
        }
    }

    @Test
    fun actualConscryptConstructsAnchorAndEnforcesAdditionalRootAndLeafDenies() {
        val root = HeldCertificate.Builder().certificateAuthority(1).commonName("Native private CA").build()
        val leaf = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root).build()
        val manager = manager(root.certificate)
        val path = X509TrustManagerExtensions(manager).checkServerTrusted(arrayOf(leaf.certificate), "RSA", "localhost")
        assertTrue(path.any { CertificateTrust.spkiHash(it) == CertificateTrust.spkiHash(root.certificate) })
        val server = server(leaf)
        try {
            for (deny in listOf(emptySet(), setOf(CertificateTrust.spkiHash(root.certificate)), setOf(CertificateTrust.spkiHash(leaf.certificate)))) {
                val client = CertificateTrust.clientBuilder(manager, deny).retryOnConnectionFailure(false).build()
                try {
                    val request = Request.Builder().url(server.url("/")).build()
                    if (deny.isEmpty()) {
                        server.enqueue(MockResponse().setBody("ok"))
                        client.newCall(request).execute().use { assertEquals(200, it.code) }
                    } else {
                        val error = certificateFailure(client, request)
                        assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it.message?.contains("distrusted public key") == true })
                    }
                } finally { close(client) }
            }
            assertEquals(1, server.requestCount)
        } finally { server.shutdown() }
    }

    @Test
    fun actualConscryptAndOkHttpRetainHostnameAndUnknownCaChecks() {
        val root = HeldCertificate.Builder().certificateAuthority(1).commonName("Native private CA").build()
        val other = HeldCertificate.Builder().certificateAuthority(1).commonName("Other private CA").build()
        val leaf = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root).build()
        val server = server(leaf)
        try {
            val trusted = CertificateTrust.clientBuilder(manager(root.certificate)).retryOnConnectionFailure(false).build()
            val unknown = CertificateTrust.clientBuilder(manager(other.certificate)).retryOnConnectionFailure(false).build()
            try {
                val wrongHost = Request.Builder().url(server.url("/").newBuilder().host("127.0.0.1").build()).build()
                assertThrows(SSLException::class.java) { trusted.newCall(wrongHost).execute().close() }
                val request = Request.Builder().url(server.url("/")).build()
                certificateFailure(unknown, request)
            } finally { close(trusted); close(unknown) }
            assertEquals(0, server.requestCount)
        } finally { server.shutdown() }
    }

    @Test
    fun actualConscryptRetainsExpiryAndSignatureChecks() {
        val root = HeldCertificate.Builder().certificateAuthority(1).commonName("Native private CA").build()
        val now = System.currentTimeMillis()
        val expired = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root)
            .validityInterval(now - TimeUnit.DAYS.toMillis(2), now - TimeUnit.DAYS.toMillis(1)).build()
        val valid = HeldCertificate.Builder().commonName("localhost").addSubjectAlternativeName("localhost").signedBy(root).build()
        val corrupted = valid.certificate.encoded.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
        val badSignature = HeldCertificate(valid.keyPair,
            CertificateFactory.getInstance("X.509").generateCertificate(corrupted.inputStream()) as X509Certificate)
        for (leaf in listOf(expired, badSignature)) {
            val server = server(leaf)
            val client = CertificateTrust.clientBuilder(manager(root.certificate)).retryOnConnectionFailure(false).build()
            try {
                certificateFailure(client, Request.Builder().url(server.url("/")).build())
                assertEquals(0, server.requestCount)
            } finally { close(client); server.shutdown() }
        }
    }

    @Test
    fun actualDefaultNetworkSecurityConfigDeniesPreviouslyValidRootAndLeaf() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("tuistTrustLive") == "true")
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(null as KeyStore?) }
        val manager = factory.trustManagers.filterIsInstance<X509TrustManager>().single()
        assertEquals("android.security.net.config.RootTrustManager", manager.javaClass.name)
        val request = Request.Builder().url("https://letsencrypt.org/").build()
        val baseline = CertificateTrust.clientBuilder(manager).build()
        val path = try {
            baseline.newCall(request).execute().use {
                assertEquals(200, it.code)
                requireNotNull(it.handshake).peerCertificates.map { certificate -> certificate as X509Certificate }
            }
        } finally { close(baseline) }
        assertTrue(path.size >= 2)
        assertEquals(path.last().subjectX500Principal, path.last().issuerX500Principal)
        path.last().verify(path.last().publicKey)
        for (certificate in listOf(path.first(), path.last())) {
            val client = CertificateTrust.clientBuilder(manager, setOf(CertificateTrust.spkiHash(certificate)))
                .retryOnConnectionFailure(false).build()
            try {
                val error = certificateFailure(client, request)
                assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it.message?.contains("distrusted public key") == true })
            } finally { close(client) }
        }
    }

    @Test
    fun publicControlsThroughActualDefaultAndroidTrustManager() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("tuistTrustLive") == "true")
        val client = CertificateTrust.clientBuilder().connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false).build()
        // Reference control only, never a production retry: ordinary native TLS,
        // no credentials, to distinguish platform distrust from our application deny.
        val reference = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).readTimeout(15, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false).build()
        var referenceAccepted = 0
        try {
            for (issuer in listOf("emudhra", "aaa-emudhra")) {
                for (prefix in listOf("dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c")) {
                    val request = Request.Builder().url("https://$prefix-$issuer.we-have-a-problem.com/").build()
                    try {
                        reference.newCall(request).execute().use { if (it.code == 200) referenceAccepted++ }
                    } catch (error: SSLHandshakeException) {
                        assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it is java.security.cert.CertificateException })
                    }
                    certificateFailure(client, request)
                }
            }
            client.newCall(Request.Builder().url("https://letsencrypt.org/").build()).execute().use { assertEquals(200, it.code) }
            android.util.Log.i("TuistTrustQualification", "Native baseline accepted $referenceAccepted/12 controls; policy client accepted 0/12")
        } finally { close(client); close(reference) }
    }

    private fun certificateFailure(client: OkHttpClient, request: Request): SSLHandshakeException {
        val error = assertThrows(SSLHandshakeException::class.java) { client.newCall(request).execute().close() }
        assertTrue(generateSequence(error as Throwable?) { it.cause }.any { it is java.security.cert.CertificateException })
        return error
    }

    private fun manager(root: X509Certificate): X509TrustManager {
        val store = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null); setCertificateEntry("private", root) }
        return TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
            .trustManagers.filterIsInstance<X509TrustManager>().single()
    }

    private fun server(leaf: HeldCertificate): MockWebServer = MockWebServer().apply {
        useHttps(HandshakeCertificates.Builder().heldCertificate(leaf).build().sslSocketFactory(), false)
        start()
    }

    private fun fixtures(name: String): List<X509Certificate> =
        InstrumentationRegistry.getInstrumentation().context.assets.open("certificate-trust/$name").use {
            CertificateFactory.getInstance("X.509").generateCertificates(it).map { certificate -> certificate as X509Certificate }
        }

    private fun close(client: OkHttpClient) {
        client.connectionPool.evictAll()
        client.dispatcher.executorService.shutdown()
    }
}
