package dev.tuist.atlas

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject

typealias AtlasAccountRequest = (JSONObject, (Result<JSONObject>) -> Unit) -> Unit

// Retained across configuration changes. Never keep an Activity, View, or subscription token here.
class AtlasAIAccountsModel(
    recoveredLoginId: String? = null,
    private val request: AtlasAccountRequest,
) {
    var listener: (() -> Unit)? = null
    var page = "settings"
        private set
    var login: JSONObject? = null
        private set
    var message: String? = null
        private set
    private var providers = JSONArray()
    private var pendingRequests = 0
    private var generation = 0
    private var pageVersion = 0
    private var loginDeadline = 0L
    private var pendingCancellation = recoveredLoginId
    private val handler = Handler(Looper.getMainLooper())
    val busy: Boolean get() = pendingRequests > 0
    val pendingLoginId: String? get() = login?.optString("login_id") ?: pendingCancellation

    fun metadata(provider: String): JSONObject? =
        (0 until providers.length()).map { providers.getJSONObject(it) }.firstOrNull { it.optString("provider") == provider }

    fun open(page: String) {
        this.page = page
        pageVersion += 1
        message = null
        changed()
    }

    fun load() {
        val pending = pendingCancellation
        if (pending != null) cancel(pending) else readMetadata()
    }

    private fun readMetadata(complete: () -> Unit = {}) {
        perform(JSONObject().put("action", "list")) { result ->
            result.onSuccess { providers = it.getJSONArray("providers") }
            complete()
        }
    }

    fun saveClaude(token: String) {
        if (busy) return
        val form = pageVersion
        perform(JSONObject().put("action", "connect_claude").put("token", token)) { result ->
            result.onSuccess {
                if (page == "claude" && form == pageVersion) page = "settings"
                readMetadata()
            }
        }
    }

    fun disconnect(provider: String) {
        if (busy || (provider == "chatgpt" && login != null)) return
        perform(JSONObject().put("action", "disconnect").put("provider", provider)) { result ->
            result.onSuccess {
                if (provider == "chatgpt") pendingCancellation = null
                readMetadata()
            }
        }
    }

    fun startSignIn() {
        if (busy || login != null) return
        if (pendingCancellation != null) {
            load()
            return
        }
        val current = ++generation
        perform(JSONObject().put("action", "start_chatgpt")) { result ->
            result.onSuccess { started ->
                if (generation != current) {
                    cancel(started.getString("login_id"))
                } else {
                    loginDeadline = SystemClock.elapsedRealtime() + 900_000
                    login = started
                    schedulePoll(current)
                }
            }
        }
    }

    private fun schedulePoll(current: Int) {
        val pending = login ?: return
        handler.postDelayed({
            if (current == generation && login != null) {
                if (SystemClock.elapsedRealtime() >= loginDeadline) {
                    cancelLogin("ChatGPT sign-in expired. Start again.")
                    return@postDelayed
                }
                perform(JSONObject().put("action", "poll_chatgpt").put("login_id", pending.getString("login_id")), quiet = true) { result ->
                    if (current == generation) {
                        message = result.exceptionOrNull()?.message
                        result.onSuccess {
                            if (it.optString("status") == "connected") {
                                login = null
                                readMetadata()
                            } else {
                                schedulePoll(current)
                            }
                        }
                        result.onFailure {
                            if ((it as? AuthFailure)?.kind in listOf("login_expired", "login_failed", "sign_in_required", "rejected")) {
                                login = null
                            } else {
                                schedulePoll(current)
                            }
                        }
                    }
                }
            }
        }, pending.getLong("interval") * 1000)
    }

    fun cancelLogin(messageAfter: String? = null) {
        generation += 1
        handler.removeCallbacksAndMessages(null)
        val pending = pendingLoginId
        login = null
        message = messageAfter
        if (pending != null) cancel(pending, messageAfter) else changed()
    }

    private fun cancel(
        id: String,
        messageAfter: String? = null,
    ) {
        pendingCancellation = id
        perform(JSONObject().put("action", "cancel_chatgpt").put("login_id", id)) { result ->
            val failure = result.exceptionOrNull()?.takeUnless { (it as? AuthFailure)?.kind == "login_expired" }
            if (failure == null) pendingCancellation = null
            message = null
            readMetadata {
                message = failure?.message ?: messageAfter
            }
        }
    }

    private fun perform(
        action: JSONObject,
        quiet: Boolean = false,
        complete: (Result<JSONObject>) -> Unit,
    ) {
        pendingRequests += 1
        val context = pageVersion
        if (!quiet) changed()
        request(action) { result ->
            pendingRequests -= 1
            val previous = message
            if (!quiet && context == pageVersion) message = result.exceptionOrNull()?.message
            complete(result)
            if (!quiet || message != previous || (login == null && !busy)) changed()
        }
    }

    private fun changed() {
        listener?.invoke()
    }
}
