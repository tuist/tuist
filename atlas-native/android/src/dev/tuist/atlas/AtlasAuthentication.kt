package dev.tuist.atlas

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object AtlasAuth {
    init {
        System.loadLibrary("atlas_auth")
    }

    external fun execute(input: String): String
}

class AtlasSecureStorage(
    context: Context,
) {
    private val preferences = context.getSharedPreferences("atlas.oauth", Context.MODE_PRIVATE)
    private val alias = "dev.tuist.atlas.oauth"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec
                    .Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .build(),
            )
            generateKey()
        }
    }

    fun load(name: String): JSONObject? {
        val stored = preferences.getString(name, null) ?: return null
        val envelope = JSONObject(stored)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(128, Base64.decode(envelope.getString("iv"), Base64.NO_WRAP)),
        )
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val data = cipher.doFinal(Base64.decode(envelope.getString("data"), Base64.NO_WRAP))
        return JSONObject(String(data, Charsets.UTF_8))
    }

    fun save(
        name: String,
        value: JSONObject,
    ) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val encrypted = cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8))
        val envelope =
            JSONObject()
                .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
                .put("data", Base64.encodeToString(encrypted, Base64.NO_WRAP))
        check(preferences.edit().putString(name, envelope.toString()).commit())
    }

    fun delete(name: String) {
        check(preferences.edit().remove(name).commit())
    }
}

internal class AuthFailure(
    val kind: String,
    message: String,
) : Exception(message)

// One coordinator per app session serializes credential rotation, not unrelated API work.
// Native secure storage and browser presentation stay outside the Rust networking crate.
class AtlasAuthentication(
    context: Context,
) {
    private val storage = AtlasSecureStorage(context.applicationContext)
    private val worker = Executors.newSingleThreadExecutor()
    private val requests = Executors.newFixedThreadPool(4)
    private val watches = Executors.newFixedThreadPool(2)

    @Volatile private var generation = 0
    val sessionGeneration: Int get() = generation
    private val main = Handler(Looper.getMainLooper())
    private val preferences = context.getSharedPreferences("atlas.settings", Context.MODE_PRIVATE)
    var listener: (() -> Unit)? = null
    var authorizationURL: String? = null
    private var deferredCallback: String? = null

    fun close() {
        worker.shutdown()
        requests.shutdown()
        watches.shutdown()
        listener = null
    }

    var server: String? = null
        private set
    var busy = false
        private set
    var errorMessage: String? = null
        private set
    val selfHostedAddress: String
        get() = preferences.getString("server", "") ?: ""

    fun restore() {
        work {
            val saved = storage.load("session") ?: return@work
            try {
                accept(command(JSONObject().put("operation", "restore").put("session", saved)))
            } catch (failure: AuthFailure) {
                if (failure.kind == "rejected") storage.delete("session")
                throw failure
            }
        }
    }

    fun signIn(
        address: String,
        selfHosted: Boolean,
    ) {
        work {
            storage.delete("automation.admission")
            val request = JSONObject().put("operation", "begin").put("server", address)
            storage.load("registration")?.let { request.put("registration", it) }
            val login = command(request)
            storage.save("registration", login.getJSONObject("registration"))
            storage.save("pending", login.getJSONObject("pending"))
            if (selfHosted) check(preferences.edit().putString("server", address).commit())
            val url = login.getString("authorization_url")
            main.post { authorizationURL = url }
        }
    }

    fun callback(url: String) {
        if (busy) {
            deferredCallback = url
            return
        }
        work {
            val pending = storage.load("pending") ?: throw AuthFailure("callback", "No sign-in is waiting for this callback.")
            try {
                accept(command(JSONObject().put("operation", "complete").put("pending", pending).put("callback", url)))
                storage.delete("pending")
            } catch (failure: AuthFailure) {
                if (failure.kind == "rejected" || failure.kind == "denied") storage.delete("pending")
                throw failure
            }
        }
    }

    fun signOut() {
        if (busy) return
        generation += 1
        work {
            storage.delete("automation.admission")
            storage.delete("session")
            storage.delete("pending")
            main.post { server = null }
        }
    }

    fun pendingLaunch(callback: (JSONObject?) -> Unit) {
        val epoch = generation
        worker.execute {
            val pending =
                try {
                    storage.load("automation.admission")
                } catch (_: Exception) {
                    null
                }
            main.post { if (epoch == generation) callback(pending) }
        }
    }

    fun native(
        request: JSONObject,
        current: () -> Boolean = { true },
        callback: (Result<JSONObject>) -> Unit,
    ) {
        val epoch = generation
        worker.execute prepare@{
            if (!current()) return@prepare
            try {
                check(epoch == generation)
                val saved = storage.load("session") ?: throw AuthFailure("unauthorized", "Sign in to Atlas first.")
                val restored = command(JSONObject().put("operation", "restore").put("session", saved))
                check(epoch == generation)
                storage.save("session", restored)
                if (request.optString("action") == "run") {
                    val pending = storage.load("automation.admission")
                    if (pending != null && canonical(pending) != canonical(request)) {
                        throw AuthFailure("pending_launch", "Retry your pending launch before starting another workflow.")
                    }
                    storage.save("automation.admission", request)
                }
                val executor = if (request.optString("action") == "watch") watches else requests
                executor.execute api@{
                    if (epoch != generation || !current()) return@api
                    val result =
                        runCatching {
                            command(JSONObject().put("operation", "native").put("session", restored).put("request", request))
                        }
                    worker.execute completion@{
                        if (epoch != generation) return@completion
                        val definitive = (result.exceptionOrNull() as? AuthFailure)?.kind in setOf("invalid_input", "revision_changed")
                        if ((result.isSuccess || definitive) && request.optString("action") == "run") {
                            try {
                                storage.delete("automation.admission")
                            } catch (_: Exception) {
                                // Retain for safe replay.
                            }
                        }
                        main.post { if (epoch == generation) callback(result) }
                    }
                }
            } catch (failure: Exception) {
                val error = if (failure is AuthFailure) failure else AuthFailure("storage", "Could not access secure Atlas credentials.")
                main.post { if (epoch == generation) callback(Result.failure(error)) }
            }
        }
    }

    private fun canonical(value: Any?): String =
        when (value) {
            is JSONObject ->
                value.keys().asSequence().toList().sorted().joinToString(prefix = "{", postfix = "}") {
                    JSONObject.quote(it) + ":" +
                        canonical(value.get(it))
                }
            is org.json.JSONArray -> (0 until value.length()).joinToString(prefix = "[", postfix = "]") { canonical(value.get(it)) }
            is String -> JSONObject.quote(value)
            else -> value?.toString() ?: "null"
        }

    private fun accept(session: JSONObject) {
        storage.save("session", session)
        val address = session.getJSONObject("registration").getString("server")
        main.post { server = address }
    }

    private fun command(request: JSONObject): JSONObject {
        val result = JSONObject(AtlasAuth.execute(request.toString()))
        result.optJSONObject("error")?.let {
            throw AuthFailure(it.getString("kind"), it.getString("message"))
        }
        return result.getJSONObject("ok")
    }

    private fun work(action: () -> Unit) {
        if (busy) return
        busy = true
        errorMessage = null
        listener?.invoke()
        worker.execute {
            var failure: String? = null
            try {
                action()
            } catch (error: AuthFailure) {
                if (error.kind == "rejected") {
                    try {
                        storage.delete("registration")
                    } catch (_: Exception) {
                        // Preserve the credential failure without exposing storage details.
                    }
                }
                failure = error.message
            } catch (_: Exception) {
                failure = "Could not access secure Atlas credentials. Try again."
            }
            main.post {
                busy = false
                errorMessage = failure
                listener?.invoke()
                deferredCallback?.let { url ->
                    deferredCallback = null
                    callback(url)
                }
            }
        }
    }
}
