package dev.tuist.atlas

import org.json.JSONObject

class AtlasConnectionsModel(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    var listener: (() -> Unit)? = null
    var showing = false
    var connections = emptyList<JSONObject>()
        private set
    var busy = false
        private set
    var waiting = false
        private set
    var message: String? = null
        private set
    var authorizationURL: String? = null
    private var generation = 0

    fun load() {
        if (busy || waiting) return
        perform(JSONObject().put("action", "list")) { response ->
            val rows = response.getJSONArray("connections")
            connections = (0 until rows.length()).map(rows::getJSONObject)
        }
    }

    fun connect(provider: String) {
        if (busy || waiting) return
        perform(JSONObject().put("action", "begin").put("provider", provider)) { response ->
            waiting = true
            authorizationURL = response.getString("authorization_url")
        }
    }

    fun callback(
        url: String,
        completed: (Boolean) -> Unit,
    ) {
        if (busy) {
            completed(false)
            return
        }
        val epoch = generation
        busy = true
        request(JSONObject().put("action", "complete").put("callback", url)) { result ->
            if (epoch != generation) return@request
            busy = false
            result.fold({ response ->
                waiting = false
                showing = true
                load()
                if (response.getString("status") != "connected") message = "The account was not connected. Try again."
                completed(true)
            }, {
                message = it.message
                completed(false)
            })
            listener?.invoke()
        }
    }

    fun cancel() {
        if (busy) return
        perform(JSONObject().put("action", "cancel")) {
            waiting = false
            authorizationURL = null
            message = "Connection cancelled."
        }
    }

    fun disconnect(provider: String) {
        if (busy || waiting) return
        perform(JSONObject().put("action", "disconnect").put("provider", provider)) { load() }
    }

    fun clear() {
        generation += 1
        connections = emptyList()
        authorizationURL = null
        message = null
        waiting = false
        busy = false
        listener = null
    }

    private fun perform(
        action: JSONObject,
        success: (JSONObject) -> Unit,
    ) {
        val epoch = generation
        busy = true
        message = null
        listener?.invoke()
        request(action) { result ->
            if (epoch != generation) return@request
            busy = false
            result.fold(success, { message = it.message })
            listener?.invoke()
        }
    }
}
