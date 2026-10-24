package dev.tuist.atlas

import org.json.JSONArray
import org.json.JSONObject

// Thin adapter over the Rust `orbit_session` handle. Rust owns thread state, pagination,
// stale-request guards, drafts, client IDs and the live connection; this class only forwards commands,
// applies newer snapshots and keeps view-only state (create form, Ask toggle, expanded tool cards).
class AtlasOrbitModel(
    private val request: (JSONObject, (Result<JSONObject>) -> Unit) -> Unit,
) {
    data class Assistant(
        val name: String,
        val configured: Boolean,
    )

    data class Person(
        val id: String,
        val name: String,
    )

    data class Thread(
        val id: String,
        val title: String,
        val kind: String,
        val status: String,
        val summary: String,
        val participants: List<Person>,
        val updatedAt: String,
    ) {
        val isPrivate get() = kind == "private"
        val archived get() = status == "archived"
    }

    data class Message(
        val id: String,
        val kind: String,
        val body: String,
        val authorId: String?,
        val authorName: String,
        val insertedAt: String,
        val toolName: String?,
        val toolStatus: String?,
        val toolInput: String,
        val toolOutput: String,
        val component: String? = null,
    ) {
        val isTool get() = kind == "tool" || toolName != null
    }

    data class Viewer(
        val id: String,
        val name: String,
        val typing: Boolean,
    )

    data class Snapshot(
        val sequence: Long = 0,
        val assistant: Assistant? = null,
        val threads: List<Thread> = emptyList(),
        val selected: Thread? = null,
        val messages: List<Message> = emptyList(),
        val people: List<Viewer> = emptyList(),
        val draft: String = "",
        val loading: Boolean = false,
        val historyLoading: Boolean = false,
        val saving: Boolean = false,
        val hasMore: Boolean = false,
        val hasOlder: Boolean = false,
        val error: String? = null,
        val liveMessage: String? = null,
        val needsSession: Boolean = false,
        val selectionId: String? = null,
        val hasDrafts: Boolean = false,
    ) {
        val privateThread get() = threads.firstOrNull { it.isPrivate }
        val shared get() = threads.filter { !it.isPrivate }
    }

    data class CreateDraft(
        val title: String,
        val participants: Set<String>,
    )

    var listener: (() -> Unit)? = null
    var snapshot = Snapshot()
        private set

    // Adapter failures (opening the handle, credential or transport errors) that Rust could not report.
    var failure: String? = null
        private set
    var createDraft: CreateDraft? = null
        private set
    var expandedTools = emptySet<String>()
        private set
    var revealedEvidence = emptySet<String>()
        private set

    // Local draft writes still in flight; the view must not overwrite what the person is typing with an older echo.
    var draftsInFlight = 0
        private set
    private val askAssistant = mutableMapOf<String, Boolean>()
    private var connection: String? = null
    private var opening = false
    private var closed = false
    private var active = false
    private var receiving = 0
    private var renewing = false
    private var renewed = false
    private val queued = mutableListOf<JSONObject>()
    private var pendingSelection: String? = null

    // Covers the gap between tapping Send and Rust reporting `saving`, so a double tap sends once.
    private var submitting = false
    val sending get() = submitting || snapshot.saving

    val selectionId get() = pendingSelection ?: snapshot.selectionId ?: snapshot.selected?.id
    val selecting get() = pendingSelection != null
    val canBack get() = createDraft != null || selectionId != null
    val hasProtectedWork get() = createDraft != null || sending || draftsInFlight > 0 || snapshot.hasDrafts || snapshot.draft.isNotBlank()

    fun open() {
        if (closed || opening || connection != null) return
        opening = true
        failure = null
        request(JSONObject().put("action", "open")) { result ->
            opening = false
            val handle = result.getOrNull()?.optString("connection")?.takeIf { it.isNotEmpty() }
            if (closed) {
                handle?.let(::close)
                return@request
            }
            if (handle == null) {
                failure = result.exceptionOrNull()?.message ?: "Orbit is unavailable. Try again."
                listener?.invoke()
                return@request
            }
            connection = handle
            if (active) command(JSONObject().put("action", "active").put("active", true))
            if (queued.none { it.getString("action") == "load" }) command(JSONObject().put("action", "load"))
            queued.toList().also { queued.clear() }.forEach(::command)
            receive()
        }
    }

    fun setActive(value: Boolean) {
        if (active == value || closed) return
        active = value
        val handle = connection
        if (handle == null) {
            if (value) open()
            return
        }
        if (value) {
            // Resuming goes through the coordinator so the live connection starts with refreshed credentials.
            command(JSONObject().put("action", "active").put("active", true))
            receive()
        } else {
            local(JSONObject().put("action", "active").put("connection", handle).put("active", false))
        }
    }

    fun close() {
        if (closed) return
        closed = true
        listener = null
        queued.clear()
        pendingSelection = null
        connection?.let(::close)
        connection = null
        snapshot = Snapshot()
    }

    fun load() = command(JSONObject().put("action", "load"))

    fun loadMore() = command(JSONObject().put("action", "load_more"))

    fun openPrivate() = command(JSONObject().put("action", "private"))

    fun select(id: String) {
        pendingSelection = id
        queued.removeAll { it.optString("action") == "select" }
        expandedTools = emptySet()
        revealedEvidence = emptySet()
        command(JSONObject().put("action", "select").put("id", id))
        listener?.invoke()
    }

    fun leave() {
        val id = selectionId ?: return
        if (connection == null) {
            queued.removeAll { it.optString("action") == "select" }
            pendingSelection = null
            listener?.invoke()
            return
        }
        command(JSONObject().put("action", "leave").put("id", id))
    }

    fun showList() {
        if (selectionId != null) leave()
    }

    fun loadOlder() = command(JSONObject().put("action", "history").put("older", true))

    fun refresh() = command(JSONObject().put("action", if (selectionId == null) "load" else "refresh"))

    fun back(): Boolean {
        when {
            createDraft != null -> discardCreate()
            selectionId != null -> leave()
            else -> return false
        }
        return true
    }

    // View preference only; Rust decides who a message addresses (private threads always reach the assistant).
    fun askAssistant(id: String) = askAssistant[id] == true

    fun setAskAssistant(
        id: String,
        value: Boolean,
    ) {
        askAssistant[id] = value
        listener?.invoke()
    }

    // Rust keeps the canonical draft and the client ID it reuses when a failed send is retried.
    // The thread ID is captured when the person types, not when the write runs.
    fun setDraft(
        id: String,
        value: String,
    ) {
        val handle = connection ?: return
        draftsInFlight += 1
        local(
            JSONObject()
                .put("action", "draft")
                .put("connection", handle)
                .put("id", id)
                .put("body", value),
        ) { draftsInFlight -= 1 }
    }

    // The body is captured at the tap, so draft writes or credential restore that finish later cannot change
    // what is sent. Rust reuses the client ID when the same body is retried and never clears a newer draft.
    fun send(
        id: String,
        body: String,
    ) {
        if (sending || body.isBlank()) return
        submitting = true
        command(
            JSONObject()
                .put("action", "send")
                .put("id", id)
                .put("body", body)
                .put("address_agent", askAssistant(id)),
        )
        listener?.invoke()
    }

    fun componentAction(
        messageId: String,
        event: String,
    ) {
        val handle = connection ?: return
        val id = snapshot.selected?.id ?: return
        request(
            JSONObject()
                .put("action", "component_action")
                .put("connection", handle)
                .put("id", id)
                .put("message_id", messageId)
                .put("event", event),
        ) { result ->
            val effect = result.getOrNull()
            if (!closed && snapshot.selected?.id == id && effect?.optString("effect") == "show_evidence" &&
                effect.optString("thread_id") == id && effect.optString("message_id") == messageId &&
                snapshot.messages.any { it.id == messageId }
            ) {
                revealedEvidence = revealedEvidence + messageId
                listener?.invoke()
            }
        }
    }

    fun toggleTool(id: String) {
        expandedTools = if (id in expandedTools) expandedTools - id else expandedTools + id
        listener?.invoke()
    }

    fun startCreate() {
        if (createDraft != null) return
        createDraft = CreateDraft("", emptySet())
        listener?.invoke()
    }

    fun setCreateTitle(value: String) {
        createDraft = createDraft?.copy(title = value)
    }

    fun toggleParticipant(id: String) {
        val draft = createDraft ?: return
        createDraft = draft.copy(participants = if (id in draft.participants) draft.participants - id else draft.participants + id)
        listener?.invoke()
    }

    fun discardCreate() {
        if (snapshot.saving || snapshot.loading) return
        createDraft = null
        listener?.invoke()
    }

    // Rust selects the new thread itself; the form closes only once the snapshot shows it.
    fun create() {
        val draft = createDraft ?: return
        val title = draft.title.trim()
        if (title.isEmpty() || snapshot.saving || snapshot.loading) return
        command(
            JSONObject()
                .put("action", "create")
                .put("title", title)
                .put("participant_ids", JSONArray(draft.participants.sorted())),
        )
    }

    private fun command(value: JSONObject) {
        if (closed) return
        val handle = connection
        if (handle == null) {
            queued.add(value)
            open()
            return
        }
        failure = null
        val action = value.getString("action")
        request(JSONObject().put("action", "request").put("connection", handle).put("command", value)) { result ->
            if (action == "send") submitting = false
            if (closed || connection != handle) return@request
            if (action == "select" && pendingSelection == value.optString("id")) pendingSelection = null
            result.fold({ value ->
                apply(value)
                if (action == "create" && snapshot.error == null && snapshot.selected != null) createDraft = null
            }, { failure = it.message ?: "Could not update threads. Try again." })
            if (action == "active" || action == "refresh") deactivateIfBackground(handle)
            listener?.invoke()
        }
    }

    private fun local(
        value: JSONObject,
        finished: () -> Unit = {},
    ) {
        val handle = value.getString("connection")
        request(value) { result ->
            finished()
            if (closed || connection != handle) return@request
            result.getOrNull()?.let {
                apply(it)
                listener?.invoke()
            }
        }
    }

    // One bounded wait at a time per foreground period; the loop stops in the background or after close.
    private fun receive() {
        val handle = connection ?: return
        if (!active || closed || receiving > 0) return
        receiving += 1
        request(JSONObject().put("action", "next").put("connection", handle).put("after", snapshot.sequence)) { result ->
            receiving -= 1
            if (closed || connection != handle) return@request
            val value = result.getOrNull()
            if (value == null) {
                connection = null
                snapshot = Snapshot()
                failure = "Orbit disconnected. Refresh to reconnect."
                listener?.invoke()
                return@request
            }
            if (apply(value)) listener?.invoke()
            receive()
        }
    }

    // Snapshots are monotonic; older results from racing calls are ignored.
    private fun apply(value: JSONObject): Boolean {
        val next =
            try {
                parse(value)
            } catch (_: Exception) {
                failure = "Atlas returned an invalid thread update. Try refreshing."
                return true
            }
        if (next.sequence <= snapshot.sequence && snapshot.sequence != 0L) return false
        snapshot = next
        if (!next.needsSession) renewed = false
        // Renew once per expiry: the refresh request restores credentials and Rust reconnects live viewing.
        if (next.needsSession && !renewing && !renewed) {
            renewing = true
            renewed = true
            val handle = connection ?: return true
            request(JSONObject().put("action", "request").put("connection", handle).put("command", JSONObject().put("action", "refresh"))) {
                renewing = false
                if (closed || connection != handle) return@request
                it.getOrNull()?.let(::apply)
                deactivateIfBackground(handle)
                listener?.invoke()
            }
        }
        return true
    }

    // Activation and refresh travel through the credential queue while deactivation is local, so one that
    // lands after the app went back to the background could reopen live viewing; undo it.
    private fun deactivateIfBackground(handle: String) {
        if (!active) local(JSONObject().put("action", "active").put("connection", handle).put("active", false))
    }

    private fun close(handle: String) {
        request(JSONObject().put("action", "close").put("connection", handle)) {}
    }

    private fun parse(value: JSONObject) =
        Snapshot(
            value.getLong("sequence"),
            value.optJSONObject("assistant")?.let { Assistant(it.getString("name"), it.getBoolean("configured")) },
            value.getJSONArray("threads").objects().map(::thread),
            value.optJSONObject("selected")?.let(::thread),
            value.getJSONArray("messages").objects().map(::message),
            value.getJSONArray("people").objects().map { Viewer(it.getString("id"), it.getString("name"), it.optBoolean("typing")) },
            value.optString("draft"),
            value.optBoolean("loading"),
            value.optBoolean("history_loading"),
            value.optBoolean("saving"),
            value.optBoolean("has_more"),
            value.optBoolean("has_older"),
            value.nullableString("error"),
            value.nullableString("live_message"),
            value.optBoolean("needs_session"),
            value.nullableString("selection_id"),
            value.optBoolean("has_drafts"),
        )

    private fun thread(value: JSONObject) =
        Thread(
            value.getString("id"),
            value.getString("title"),
            value.getString("kind"),
            value.getString("status"),
            value.optString("summary"),
            value.optJSONArray("participants")?.objects()?.map { Person(it.getString("id"), it.getString("name")) } ?: emptyList(),
            value.getString("updated_at"),
        )

    private fun message(value: JSONObject) =
        Message(
            value.getString("id"),
            value.getString("kind"),
            value.optString("body"),
            value.nullableString("author_id"),
            value.optString("author_name"),
            value.getString("inserted_at"),
            value.nullableString("tool_name"),
            value.nullableString("tool_status"),
            value.optString("tool_input"),
            value.optString("tool_output"),
            value.optJSONObject("component")?.toString(),
        )

    private fun JSONObject.nullableString(key: String) = if (!has(key) || isNull(key)) null else optString(key)

    private fun JSONArray.objects() = List(length()) { getJSONObject(it) }
}
