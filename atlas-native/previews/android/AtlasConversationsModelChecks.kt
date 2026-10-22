package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasConversationsModel
import org.json.JSONObject

private const val PRIVATE = "01922cc0-0000-7000-8000-000000000001"
private const val SHARED = "01922cc0-0000-7000-8000-000000000002"

internal fun checkConversationsModel() {
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasConversationsModel { action, done -> pending.add(action to done) }

    fun take(
        action: String,
        command: String? = null,
    ): Pair<JSONObject, (Result<JSONObject>) -> Unit> {
        val index =
            pending.indexOfFirst {
                it.first.getString("action") == action &&
                    (command == null || it.first.optJSONObject("command")?.getString("action") == command)
            }
        check(index >= 0) { "missing $action $command" }
        return pending.removeAt(index)
    }

    fun conversation(
        id: String,
        kind: String,
    ) = JSONObject(
        """{"id":"$id","title":"Plan","kind":"$kind","status":"active","summary":"","origin":"manual","owner_id":null,"participants":[],"updated_at":"2027-06-07T10:00:00Z"}""",
    )

    fun snapshot(
        sequence: Long,
        selected: String? = null,
        draft: String = "",
        needsSession: Boolean = false,
    ) = JSONObject()
        .put("sequence", sequence)
        .put("bot", JSONObject().put("name", "Server bot").put("configured", true))
        .put(
            "conversations",
            org.json
                .JSONArray()
                .put(conversation(PRIVATE, "private"))
                .put(conversation(SHARED, "shared")),
        ).put("selected", selected?.let { conversation(it, if (it == PRIVATE) "private" else "shared") } ?: JSONObject.NULL)
        .put("messages", org.json.JSONArray())
        .put("people", org.json.JSONArray())
        .put("draft", draft)
        .put("loading", false)
        .put("saving", false)
        .put("has_more", false)
        .put("has_older", false)
        .put("error", JSONObject.NULL)
        .put("live_message", JSONObject.NULL)
        .put("needs_session", needsSession)

    // Commands issued before the handle exists wait for it; opening activates, loads once and starts waiting.
    model.setActive(true)
    model.open()
    model.load()
    take("open").second(Result.success(JSONObject("""{"connection":"handle"}""")))
    val active = take("request", "active")
    check(active.first.getJSONObject("command").getBoolean("active") && active.first.getString("connection") == "handle")
    val load = take("request", "load")
    check(pending.none { it.first.optJSONObject("command")?.getString("action") == "load" })
    val wait = take("next")
    check(wait.first.getLong("after") == 0L)
    load.second(Result.success(snapshot(2)))
    check(
        model.snapshot.privateConversation?.id == PRIVATE && model.snapshot.shared
            .single()
            .id == SHARED,
    )

    // Older racing results never replace a newer snapshot.
    active.second(Result.success(snapshot(1)))
    check(model.snapshot.sequence == 2L)

    // The wait loop continues from the latest sequence and stays single.
    wait.second(Result.success(snapshot(3, SHARED)))
    check(model.snapshot.selected?.id == SHARED && take("next").first.getLong("after") == 3L)

    // Drafts are local Rust writes scoped to the conversation typed in; echoes are tracked so the view keeps typing.
    model.setDraft(SHARED, "Hel")
    model.setDraft(SHARED, "Hello")
    val firstDraft = take("draft")
    check(model.draftsInFlight == 2 && firstDraft.first.getString("body") == "Hel" && firstDraft.first.getString("id") == SHARED)

    // A send carries the ID and body captured at the tap without waiting for draft writes; a double tap sends once.
    model.send(SHARED, "  ")
    check(!model.sending)
    model.send(SHARED, "Hello")
    model.send(SHARED, "Hello again")
    val shared = take("request", "send")
    check(shared.first.getJSONObject("command").getString("id") == SHARED)
    check(shared.first.getJSONObject("command").getString("body") == "Hello" && model.sending)
    check(pending.none { it.first.optJSONObject("command")?.getString("action") == "send" })
    firstDraft.second(Result.success(snapshot(4, SHARED, "Hel")))
    take("draft").second(Result.success(snapshot(5, SHARED, "Hello")))
    check(model.draftsInFlight == 0)

    // The adapter forwards the Ask preference only; Rust applies the private-thread rule.
    check(!shared.first.getJSONObject("command").getBoolean("address_agent"))
    shared.second(Result.success(snapshot(6, SHARED)))
    check(!model.sending)
    model.setAskBot(SHARED, true)
    model.send(SHARED, "Summarize")
    take("request", "send")
        .also {
            check(it.first.getJSONObject("command").getBoolean("address_agent"))
        }.second(Result.success(snapshot(7, SHARED)))
    model.send(PRIVATE, "Help")
    take("request", "send")
        .also {
            check(!it.first.getJSONObject("command").getBoolean("address_agent"))
        }.second(Result.success(snapshot(8, SHARED)))

    // Expired credentials trigger exactly one refresh request until a healthy snapshot arrives.
    model.select(PRIVATE)
    take("request", "select").second(Result.success(snapshot(9, PRIVATE, needsSession = true)))
    val renew = take("request", "refresh")
    model.send(PRIVATE, "Help")
    take("request", "send").second(Result.success(snapshot(10, PRIVATE, needsSession = true)))
    check(pending.none { it.first.optJSONObject("command")?.getString("action") == "refresh" })
    check(model.snapshot.selected?.isPrivate == true)
    renew.second(Result.success(snapshot(11, PRIVATE)))
    check(pending.none { it.first.getString("action") == "active" })
    check(!model.snapshot.needsSession)

    // Background deactivation is local; foreground goes through the coordinator for fresh credentials.
    model.setActive(false)
    val inactive = take("active")
    check(!inactive.first.getBoolean("active") && inactive.first.getString("connection") == "handle")
    model.setActive(true)
    take("request", "active")

    // A resume that lands after the app returned to the background is undone locally.
    model.setActive(false)
    take("active")
    model.setActive(true)
    val resume = take("request", "active")
    model.setActive(false)
    take("active")
    resume.second(Result.success(snapshot(12, PRIVATE)))
    check(!take("active").first.getBoolean("active"))
    model.setActive(true)
    take("request", "active")

    // The same applies to a renewal refresh that lands in the background.
    model.setActive(false)
    take("active")
    model.refresh()
    take("request", "refresh").second(Result.success(snapshot(13, PRIVATE)))
    check(!take("active").first.getBoolean("active"))
    model.setActive(true)
    take("request", "active")

    // Leaving and creating are Rust commands; the create form closes once Rust selects the new thread.
    model.back()
    check(take("request", "leave").first.getJSONObject("command").getString("id") == PRIVATE)
    model.startCreate()
    model.setCreateTitle("  Launch plan ")
    model.toggleParticipant(SHARED)
    model.create()
    val create = take("request", "create")
    check(create.first.getJSONObject("command").getString("title") == "Launch plan")
    check(
        create.first
            .getJSONObject("command")
            .getJSONArray("participant_ids")
            .getString(0) == SHARED,
    )
    create.second(Result.success(snapshot(20, SHARED)))
    check(model.createDraft == null && model.snapshot.selected?.id == SHARED)

    // Closing releases the handle and ignores late results.
    model.close()
    check(take("close").first.getString("connection") == "handle")
    pending.toList().forEach { it.second(Result.success(snapshot(99, PRIVATE))) }
    check(model.snapshot.sequence == 0L && model.snapshot.conversations.isEmpty())

    // A handle that opens after close is released immediately.
    val late = AtlasConversationsModel { action, done -> pending.add(action to done) }
    late.open()
    late.close()
    take("open").second(Result.success(JSONObject("""{"connection":"late"}""")))
    check(take("close").first.getString("connection") == "late")
}
