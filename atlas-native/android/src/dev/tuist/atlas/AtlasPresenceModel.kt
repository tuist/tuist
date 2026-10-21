package dev.tuist.atlas

import org.json.JSONObject

class AtlasPresenceModel(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    data class Person(
        val id: String,
        val name: String,
        val email: String,
        val online: Boolean,
        val here: Boolean,
    )

    var people = emptyList<Person>()
        private set
    var error: String? = null
        private set
    var listener: (() -> Unit)? = null
    private var connection: String? = null
    private var location = emptyMap<String, String>()
    private var active = false
    private var generation = 0
    private var opening = false
    private var updating = false
    private val stopped = mutableListOf<() -> Unit>()

    fun show(
        resource: String? = null,
        id: String? = null,
    ) {
        val next =
            buildMap {
                resource?.let { put("resource", it) }
                id?.let { put("id", it) }
            }
        if (location == next) return
        location = next
        people = emptyList()
        listener?.invoke()
        updateLocation()
    }

    fun setActive(value: Boolean) {
        if (active == value) return
        active = value
        generation += 1
        if (value) {
            open()
        } else {
            people = emptyList()
            listener?.invoke()
            connection?.let { close(it) }
            if (!opening && connection == null) finishStop()
        }
    }

    fun stop(completion: () -> Unit) {
        stopped.add(completion)
        setActive(false)
        if (!opening && connection == null) finishStop()
    }

    private fun open() {
        if (!active || opening || connection != null) return
        opening = true
        val started = generation
        request(JSONObject().put("action", "open")) { result ->
            opening = false
            val id = result.getOrNull()?.optString("connection")?.takeIf { it.isNotEmpty() }
            if (id == null) {
                error = "Presence is unavailable. Reopen Atlas to retry."
                listener?.invoke()
                finishStop()
                return@request
            }
            connection = id
            if (!active || generation != started) {
                close(id)
                return@request
            }
            updateLocation()
            receive(id, started, 0)
        }
    }

    private fun receive(
        id: String,
        started: Int,
        sequence: Long,
    ) {
        request(JSONObject().put("action", "next").put("connection", id).put("after", sequence)) { result ->
            if (connection != id || !active || generation != started) return@request
            val value = result.getOrNull()
            if (value == null) {
                error = "Presence is unavailable. Reopen Atlas to retry."
                people = emptyList()
                listener?.invoke()
                close(id, restart = false)
                return@request
            }
            if (value.optBoolean("needs_session")) {
                close(id)
                return@request
            }
            val snapshotLocation =
                value.optJSONObject("location")?.let { objectValue ->
                    objectValue.keys().asSequence().associateWith { objectValue.getString(it) }
                }
            if (value.has("error")) {
                people = emptyList()
                error = "Reconnecting to Atlas…"
            } else if (snapshotLocation == location) {
                val rows = value.getJSONArray("people")
                people =
                    List(rows.length()) { index ->
                        val person = rows.getJSONObject(index)
                        Person(
                            person.getString("id"),
                            person.getString("name"),
                            person.getString("email"),
                            person.getBoolean("online"),
                            person.getBoolean("here"),
                        )
                    }
                error = null
            }
            listener?.invoke()
            receive(id, started, value.getLong("sequence"))
        }
    }

    private fun updateLocation() {
        val id = connection ?: return
        if (!active || updating) return
        updating = true
        val sent = location
        request(JSONObject(sent).put("action", "update").put("connection", id)) {
            updating = false
            if (active && (sent != location || id != connection)) updateLocation()
        }
    }

    private fun close(
        id: String,
        restart: Boolean = true,
    ) {
        request(JSONObject().put("action", "close").put("connection", id)) {
            if (connection == id) connection = null
            finishStop()
            if (active && restart) open()
        }
    }

    private fun finishStop() {
        val callbacks = stopped.toList()
        stopped.clear()
        callbacks.forEach { it() }
    }
}
