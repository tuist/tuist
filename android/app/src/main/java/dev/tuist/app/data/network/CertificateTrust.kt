package dev.tuist.app.data.network

import android.net.http.X509TrustManagerExtensions
import android.os.Build
import androidx.annotation.Keep
import okhttp3.OkHttpClient
import java.net.Socket
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509ExtendedTrustManager
import javax.net.ssl.X509TrustManager

internal object CertificateTrust {
    // Synchronized with infra/certificate-trust/policy.json; ships inside the APK.
    val blockedSPKIHashes = setOf(
        "8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
        "bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3",
        "ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105",
        "49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f",
        "e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41",
        "5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0",
        "43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b",
        "63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8",
        "ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6",
        "92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30",
        "c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9",
        "0a6c2b2ca5b364207954171987ac9d2178561569d8205457e77ca90c32ede282",
    )

    fun spkiHash(certificate: X509Certificate): String =
        MessageDigest.getInstance("SHA-256").digest(certificate.publicKey.encoded)
            .joinToString("") { "%02x".format(it) }

    fun requireAllowed(chain: List<X509Certificate>, additionalBlocked: Set<String> = emptySet()) {
        if (chain.isEmpty()) throw CertificateException("No verified certificate chain")
        if (chain.any {
                val hash = spkiHash(it)
                hash in blockedSPKIHashes || hash in additionalBlocked
            }) {
            throw CertificateException("Certificate chain contains a distrusted public key")
        }
    }

    fun clientBuilder(
        original: X509TrustManager = systemTrustManager(),
        additionalBlocked: Set<String> = emptySet(),
    ): OkHttpClient.Builder {
        val manager = PolicyTrustManager(original, additionalBlocked)
        val context = SSLContext.getInstance("TLS")
        context.init(null, arrayOf(manager), null)
        return OkHttpClient.Builder().sslSocketFactory(context.socketFactory, manager)
    }

    private fun systemTrustManager(): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as KeyStore?)
        return factory.trustManagers.filterIsInstance<X509TrustManager>().single()
    }
}

/** Keep the public hostname-aware methods: Android/OkHttp discover them reflectively. */
@Keep
internal class PolicyTrustManager(
    private val original: X509TrustManager,
    additionalBlocked: Set<String> = emptySet(),
) : X509ExtendedTrustManager() {
    private val extensions = X509TrustManagerExtensions(original)
    private val additionalBlocked = additionalBlocked.toSet()

    override fun getAcceptedIssuers(): Array<X509Certificate> = original.acceptedIssuers.clone()

    @Throws(CertificateException::class)
    fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, hostname: String?): List<X509Certificate> {
        // This returns the constructed native path, including cached/AIA issuers
        // and its anchor, and preserves hostname-specific Network Security Config.
        val verified = extensions.checkServerTrusted(chain, authType, hostname)
        CertificateTrust.requireAllowed(verified, additionalBlocked)
        return verified
    }

    fun isSameTrustConfiguration(first: String, second: String): Boolean =
        if (Build.VERSION.SDK_INT >= 28) extensions.isSameTrustConfiguration(first, second) else true

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String) {
        original.checkServerTrusted(chain, authType)
        checkServerTrusted(chain, authType, null as String?)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) {
        if (original is X509ExtendedTrustManager) original.checkServerTrusted(chain, authType, socket)
        else original.checkServerTrusted(chain, authType)
        checkServerTrusted(chain, authType, (socket as? SSLSocket)?.handshakeSession?.peerHost)
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) {
        if (original is X509ExtendedTrustManager) original.checkServerTrusted(chain, authType, engine)
        else original.checkServerTrusted(chain, authType)
        checkServerTrusted(chain, authType, engine?.handshakeSession?.peerHost ?: engine?.peerHost)
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String) =
        original.checkClientTrusted(chain, authType)

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, socket: Socket?) {
        if (original is X509ExtendedTrustManager) original.checkClientTrusted(chain, authType, socket)
        else original.checkClientTrusted(chain, authType)
    }

    override fun checkClientTrusted(chain: Array<out X509Certificate>, authType: String, engine: SSLEngine?) {
        if (original is X509ExtendedTrustManager) original.checkClientTrusted(chain, authType, engine)
        else original.checkClientTrusted(chain, authType)
    }
}
