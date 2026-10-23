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
    var pushAvailable = false
        private set
    var busy = false
        private set
    var error: String? = null
        private set
    private var cleared = false

    fun load() {
        if (busy || cleared) return
        busy = true
        error = null
        listener?.invoke()
        request(JSONObject().put("resource", "profile").put("action", "list")) { result ->
            if (cleared) return@request
            result.fold({ response ->
                try {
                    val user = response.getJSONObject("user")
                    val nextVersion = response.getString("server_version")
                    val nextName = user.getString("name")
                    val nextEmail = user.getString("email")
                    name = nextName
                    email = nextEmail
                    version = nextVersion
                    pushAvailable = response.optJSONObject("push_notifications")?.optBoolean("android") == true
                } catch (_: Exception) {
                    error = "Could not read your Atlas profile. Try again."
                }
            }, { error = it.message ?: "Could not load your Atlas profile. Try again." })
            busy = false
            listener?.invoke()
        }
    }

    fun clear() {
        cleared = true
        listener = null
        name = ""
        email = ""
        version = ""
        pushAvailable = false
        error = null
    }
}
