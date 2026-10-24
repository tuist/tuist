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

object AtlasPushStorage {
    fun key(origin: String): String = "push-registration:$origin"
}

class AuthFailure(
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
    private val holidayWorker = Executors.newFixedThreadPool(2)

    // Presence and the thread session each block in a bounded `next` wait, leaving room for local commands.
    private val presenceWorker = Executors.newFixedThreadPool(4)

    @Volatile private var sessionIdentity = 0
    val sessionGeneration: Int get() = sessionIdentity
    private val main = Handler(Looper.getMainLooper())
    private val preferences = context.getSharedPreferences("atlas.settings", Context.MODE_PRIVATE)
    var listener: (() -> Unit)? = null
    var authorizationURL: String? = null
    private var deferredCallback: String? = null
    private var apiRequests = 0
    private var closing = false

    fun close() {
        closing = true
        requests.shutdown()
        watches.shutdown()
        if (apiRequests == 0) {
            worker.shutdown()
            holidayWorker.shutdown()
            presenceWorker.shutdown()
        }
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
            accept(command(JSONObject().put("operation", "restore").put("session", saved)))
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
        work { discardSession() }
    }

    private fun discardSession(removeRegistration: Boolean = false) {
        val origin = runCatching { storage.load("session")?.optJSONObject("registration")?.optString("server") }.getOrNull() ?: server
        origin?.let {
            val key = AtlasPushStorage.key(it)
            runCatching { storage.load(key)?.let { saved -> storage.save(key, saved.put("enabled", false)) } }
                .onFailure { runCatching { storage.delete(key) } }
        }
        storage.delete("automation.admission")
        storage.delete("session")
        sessionIdentity += 1
        main.post { server = null }
        storage.delete("pending")
        if (removeRegistration) storage.delete("registration")
    }

    fun aiAccounts(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) {
        apiRequests += 1
        worker.execute {
            val result =
                try {
                    val saved = storage.load("session") ?: throw AuthFailure("sign_in_required", "Sign in to Atlas again.")
                    val restored = command(JSONObject().put("operation", "restore").put("session", saved))
                    // Commit rotated credentials even when the following API request fails.
                    storage.save("session", restored)
                    val request = JSONObject(action.toString()).put("operation", "ai_accounts").put("session", restored)
                    Result.success(command(request))
                } catch (error: AuthFailure) {
                    if (error.kind == "rejected") {
                        try {
                            discardSession(removeRegistration = true)
                            main.post { errorMessage = error.message }
                        } catch (_: Exception) {
                            main.post { errorMessage = "Could not delete rejected Atlas credentials. Try again." }
                        }
                    }
                    Result.failure(error)
                } catch (_: Exception) {
                    Result.failure(IllegalStateException("Could not access secure Atlas credentials. Try again."))
                }
            main.post {
                apiRequests -= 1
                completion(result)
                if ((result.exceptionOrNull() as? AuthFailure)?.kind == "rejected") listener?.invoke()
                if (closing && apiRequests == 0) {
                    worker.shutdown()
                    holidayWorker.shutdown()
                    presenceWorker.shutdown()
                }
            }
        }
    }

    fun timeOff(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) = operation("time_off", action, completion)

    fun push(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) = operation("push", action, completion)

    fun business(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) = operation("business", action, completion)

    fun presence(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) = live("presence", action, completion)

    // Rust owns thread state behind one handle. Opening and commands restore credentials first;
    // draft, active(false), next and close only touch the local handle.
    fun orbitSession(
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) = live("orbit_session", action, completion)

    // Opening and requests restore the session through the credential queue; everything else only touches
    // local Rust handles and runs on its own workers so blocking waits never hold up sign-out.
    private fun live(
        name: String,
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) {
        if (action.optString("action") == "open" || action.optString("action") == "request") {
            operation(name, action, completion)
            return
        }
        apiRequests += 1
        presenceWorker.execute {
            val result = runCatching { command(JSONObject(action.toString()).put("operation", name)) }
            main.post {
                apiRequests -= 1
                completion(result)
                if (closing && apiRequests == 0) {
                    worker.shutdown()
                    holidayWorker.shutdown()
                    presenceWorker.shutdown()
                }
            }
        }
    }

    private fun operation(
        operation: String,
        action: JSONObject,
        completion: (Result<JSONObject>) -> Unit,
    ) {
        val identity = sessionIdentity
        if (closing) {
            completion(Result.failure(AuthFailure("sign_in_required", "Sign in to Atlas again.")))
            return
        }
        apiRequests += 1

        fun finish(result: Result<JSONObject>) {
            main.post {
                apiRequests -= 1
                if (identity != sessionIdentity && (operation == "presence" || operation == "orbit_session")) {
                    result.getOrNull()?.optString("connection")?.takeIf { it.isNotEmpty() }?.let { id ->
                        live(operation, JSONObject().put("action", "close").put("connection", id)) {}
                    }
                }
                completion(
                    if (identity ==
                        sessionIdentity
                    ) {
                        result
                    } else {
                        Result.failure(AuthFailure("sign_in_required", "Sign in to Atlas again."))
                    },
                )
                if ((result.exceptionOrNull() as? AuthFailure)?.kind == "rejected") listener?.invoke()
                if (closing && apiRequests == 0) {
                    worker.shutdown()
                    holidayWorker.shutdown()
                    presenceWorker.shutdown()
                }
            }
        }
        worker.execute {
            try {
                if (identity != sessionIdentity) throw AuthFailure("sign_in_required", "Sign in to Atlas again.")
                val saved = storage.load("session") ?: throw AuthFailure("sign_in_required", "Sign in to Atlas again.")
                val restored = command(JSONObject().put("operation", "restore").put("session", saved))
                storage.save("session", restored)
                // Only refresh/persistence is serialized. Networking must not hold up sign-out.
                holidayWorker.execute {
                    val result =
                        runCatching {
                            if (identity != sessionIdentity) throw AuthFailure("sign_in_required", "Sign in to Atlas again.")
                            command(JSONObject(action.toString()).put("operation", operation).put("session", restored))
                        }
                    finish(
                        result.fold({ Result.success(it) }, {
                            Result.failure(
                                if (it is AuthFailure) it else IllegalStateException("Could not complete the request. Try again."),
                            )
                        }),
                    )
                }
            } catch (failure: AuthFailure) {
                if (failure.kind == "rejected") {
                    try {
                        discardSession(removeRegistration = true)
                    } catch (_: Exception) {
                    }
                }
                finish(Result.failure(failure))
            } catch (_: Exception) {
                finish(Result.failure(IllegalStateException("Could not access secure Atlas credentials. Try again.")))
            }
        }
    }

    fun pendingLaunch(callback: (JSONObject?) -> Unit) {
        val epoch = sessionIdentity
        worker.execute {
            val pending =
                try {
                    storage.load("automation.admission")
                } catch (_: Exception) {
                    null
                }
            main.post { if (epoch == sessionIdentity) callback(pending) }
        }
    }

    fun native(
        request: JSONObject,
        current: () -> Boolean = { true },
        callback: (Result<JSONObject>) -> Unit,
    ) {
        val epoch = sessionIdentity
        if (closing) return
        apiRequests += 1

        fun finish(result: Result<JSONObject>) {
            main.post {
                apiRequests -= 1
                if (epoch == sessionIdentity && current()) callback(result)
                if (closing && apiRequests == 0) {
                    worker.shutdown()
                    holidayWorker.shutdown()
                    presenceWorker.shutdown()
                }
            }
        }
        worker.execute prepare@{
            if (!current() || epoch != sessionIdentity) {
                finish(Result.failure(AuthFailure("sign_in_required", "Sign in to Atlas again.")))
                return@prepare
            }
            try {
                val saved = storage.load("session") ?: throw AuthFailure("unauthorized", "Sign in to Atlas first.")
                val restored = command(JSONObject().put("operation", "restore").put("session", saved))
                check(epoch == sessionIdentity)
                storage.save("session", restored)
                if (request.optString("action") == "run") {
                    val pending = storage.load("automation.admission")
                    if (pending != null && canonical(pending) != canonical(request)) {
                        throw AuthFailure("pending_launch", "Retry your pending launch before starting another workflow.")
                    }
                    storage.save("automation.admission", request)
                }
                val executor = if (request.optString("action") == "watch") watches else requests
                executor.execute {
                    val result =
                        runCatching {
                            check(epoch == sessionIdentity && current())
                            command(JSONObject().put("operation", "native").put("session", restored).put("request", request))
                        }
                    worker.execute {
                        val definitive = (result.exceptionOrNull() as? AuthFailure)?.kind in setOf("invalid_input", "revision_changed")
                        if (epoch == sessionIdentity && (result.isSuccess || definitive) && request.optString("action") == "run") {
                            try {
                                storage.delete("automation.admission")
                            } catch (_: Exception) {
                                // Retain for safe replay.
                            }
                        }
                        finish(result)
                    }
                }
            } catch (failure: Exception) {
                if (failure is AuthFailure && failure.kind == "rejected") {
                    try {
                        discardSession(removeRegistration = true)
                    } catch (_: Exception) {
                    }
                    main.post { listener?.invoke() }
                }
                val error = if (failure is AuthFailure) failure else AuthFailure("storage", "Could not access secure Atlas credentials.")
                finish(Result.failure(error))
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
                        discardSession(removeRegistration = true)
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
