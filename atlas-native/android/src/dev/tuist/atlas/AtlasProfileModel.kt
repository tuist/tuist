package dev.tuist.atlas

import org.json.JSONObject

class AtlasProfileModel(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    var listener: (() -> Unit)? = null
    var name = ""
        private set
    var email = ""
        private set
    var version = ""
        private set
    var description = ""
        private set
    var loaded = false
        private set
    var draft: String? = null
        private set
    var saving = false
        private set
    var pushAvailable = false
        private set
    var busy = false
        private set
    var error: String? = null
        private set
    private var cleared = false

    val dirty: Boolean get() = draft != null && draft != description
    val valid: Boolean get() =
        draft?.let {
            it.codePointCount(0, it.length) <= 4000 && it.toByteArray(Charsets.UTF_8).size <= 16000 &&
                !it.contains('\u0000')
        } ==
            true

    fun edit() {
        if (!loaded || busy || cleared) return
        draft = description
        error = null
        listener?.invoke()
    }

    fun change(value: String) {
        if (draft != null && !saving && !cleared) draft = value
    }

    fun cancel() {
        if (saving) return
        draft = null
        error = null
        listener?.invoke()
    }

    fun save() {
        if (busy || saving || cleared || !valid) return
        saving = true
        busy = true
        error = null
        listener?.invoke()
        request(JSONObject().put("resource", "profile").put("action", "update_profile").put("description", draft)) { result ->
            if (cleared) return@request
            result.fold({ response ->
                try {
                    read(response)
                    draft = null
                } catch (_: Exception) {
                    error = "Could not read your saved profile. Your draft is kept; try again."
                }
            }, { error = it.message ?: "Could not save your profile. Your draft is kept; try again." })
            saving = false
            busy = false
            listener?.invoke()
        }
    }

    fun load() {
        if (busy || cleared || draft != null) return
        busy = true
        error = null
        listener?.invoke()
        request(JSONObject().put("resource", "profile").put("action", "list")) { result ->
            if (cleared) return@request
            result.fold({ response ->
                try {
                    read(response)
                } catch (_: Exception) {
                    error = "Could not read your Atlas profile. Try again."
                }
            }, { error = it.message ?: "Could not load your Atlas profile. Try again." })
            busy = false
            listener?.invoke()
        }
    }

    private fun read(response: JSONObject) {
        val user = response.getJSONObject("user")
        val nextVersion = response.getString("server_version")
        val nextName = user.getString("name")
        val nextEmail = user.getString("email")
        val nextDescription = user.optString("description", "")
        name = nextName
        email = nextEmail
        version = nextVersion
        description = nextDescription
        loaded = true
        pushAvailable = response.optJSONObject("push_notifications")?.optBoolean("android") == true
    }

    fun clear() {
        cleared = true
        listener = null
        name = ""
        email = ""
        version = ""
        description = ""
        draft = null
        loaded = false
        saving = false
        busy = false
        pushAvailable = false
        error = null
    }
}
