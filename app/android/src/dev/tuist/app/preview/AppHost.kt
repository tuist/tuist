package dev.tuist.app.preview

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URL
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.HttpsURLConnection

/** Platform-only I/O. Credentials are opaque to the presentation layer. */
class AppHost(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("tuist_secure_prefs", Context.MODE_PRIVATE)

    // Called by JNI on AppCore's single background executor. Never return exception text containing URLs or tokens.
    fun perform(action: String): String = try {
        val input = JSONObject(action)
        when (input.getString("type")) {
            "read" -> JSONObject().put("value", readVault() ?: JSONObject.NULL)
            "write" -> {
                val value = input.getString("value")
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.ENCRYPT_MODE, key())
                val record = JSONObject()
                    .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                    .put("ciphertext", Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
                    .toString()
                val old = preferences.getString("vault", null)
                if (!preferences.edit().putString("vault", record).commit()) {
                    // SharedPreferences publishes to memory before its disk commit completes.
                    if (old == null) preferences.edit().remove("vault").commit()
                    else preferences.edit().putString("vault", old).commit()
                    JSONObject().put("error", "vault_write_failed")
                } else JSONObject().put("ok", true)
            }
            "http" -> http(input)
            else -> JSONObject().put("error", "unsupported_host_action")
        }.toString()
    } catch (_: Exception) {
        JSONObject().put("error", "platform_io_failed").toString()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("tuist_preview_vault", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("tuist_preview_vault", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    private fun readVault(): String? {
        val record = preferences.getString("vault", null)?.let(::JSONObject) ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(record.getString("iv"), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP)), Charsets.UTF_8)
    }

    private fun http(input: JSONObject): JSONObject {
        val url = URL(input.getString("url"))
        require(url.protocol == "https" && url.userInfo == null)
        val connection = url.openConnection() as HttpsURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.requestMethod = input.getString("method")
            input.optJSONObject("headers")?.let { headers ->
                headers.keys().forEach { name -> connection.setRequestProperty(name, headers.getString(name)) }
            }
            if (input.has("body") && !input.isNull("body")) {
                connection.doOutput = true
                connection.outputStream.use { it.write(input.getString("body").toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val body = stream?.bufferedReader(Charsets.UTF_8)?.use { reader ->
                val text = StringBuilder()
                val buffer = CharArray(8192)
                while (true) {
                    val count = reader.read(buffer)
                    if (count < 0) break
                    require(text.length + count <= 8 * 1024 * 1024)
                    text.append(buffer, 0, count)
                }
                text.toString()
            } ?: ""
            return JSONObject().put("status", status).put("body", body)
        } finally {
            connection.disconnect()
        }
    }
}
