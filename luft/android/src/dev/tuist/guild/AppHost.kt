package dev.tuist.guild

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
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
    // Where the core keeps its SQLite stores, outside Auto Backup: the server holds the authoritative copy.
    private val store = File(context.applicationContext.noBackupFilesDir, "store").apply { mkdirs() }

    private companion object {
        // The core's one presence connection. It lives as long as the Rust engine, not an Activity's
        // host, so recreation keeps it; only AppCore's executor touches it.
        var socket: WebSocket? = null
    }

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
            // The core's own messages: boot steps and migrations, never tokens.
            "log" -> {
                Log.i("Luft", input.getString("message"))
                JSONObject().put("ok", true)
            }
            "store_directory" -> JSONObject().put("path", store.absolutePath)
            // The core's presence connection. The second protocol carries the access token: never log the action.
            "socket_open" -> {
                socket?.close()
                socket = null
                val protocols = input.getJSONArray("protocols").let { array -> (0 until array.length()).map(array::getString) }
                socket = WebSocket.connect(input.getString("url"), protocols)
                JSONObject().put("ok", true)
            }
            "socket_send" -> socket?.let { it.send(input.getString("text")); JSONObject().put("ok", true) }
                ?: JSONObject().put("error", "socket_closed")
            "socket_read" -> {
                val (frames, closed) = socket?.read() ?: (emptyList<String>() to true)
                JSONObject().put("frames", JSONArray(frames)).put("closed", closed)
            }
            "socket_close" -> {
                socket?.close()
                socket = null
                JSONObject().put("ok", true)
            }
            // Only connectivity counts as offline; the core then answers from its
            // store. TLS and other failures stay errors.
            "http" -> try { http(input) } catch (_: java.net.UnknownHostException) { offline() }
                catch (_: java.net.ConnectException) { offline() }
                catch (_: java.net.NoRouteToHostException) { offline() }
                catch (_: java.net.SocketTimeoutException) { offline() }
            else -> JSONObject().put("error", "unsupported_host_action")
        }.toString()
    } catch (_: Exception) {
        JSONObject().put("error", "platform_io_failed").toString()
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("tuist_luft_vault", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("tuist_luft_vault", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
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

    private fun offline() = JSONObject().put("error", "offline")

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
