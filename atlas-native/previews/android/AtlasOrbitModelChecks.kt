package dev.tuist.atlas.preview

import dev.tuist.atlas.AtlasOrbitModel
import org.json.JSONObject

private const val PRIVATE = "01922cc0-0000-7000-8000-000000000001"
private const val SHARED = "01922cc0-0000-7000-8000-000000000002"

internal fun checkOrbitModel() {
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasOrbitModel { action, done -> pending.add(action to done) }

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

    fun thread(
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
        .put("assistant", JSONObject().put("name", "Pip").put("configured", true))
        .put(
            "threads",
            org.json
                .JSONArray()
                .put(thread(PRIVATE, "private"))
                .put(thread(SHARED, "shared")),
        ).put("selected", selected?.let { thread(it, if (it == PRIVATE) "private" else "shared") } ?: JSONObject.NULL)
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
        model.snapshot.privateThread?.id == PRIVATE && model.snapshot.shared
            .single()
            .id == SHARED,
    )

    // Older racing results never replace a newer snapshot.
    active.second(Result.success(snapshot(1)))
    check(model.snapshot.sequence == 2L)

    // The wait loop continues from the latest sequence and stays single.
    wait.second(Result.success(snapshot(3, SHARED)))
    check(model.snapshot.selected?.id == SHARED && take("next").first.getLong("after") == 3L)

    // Drafts are local Rust writes scoped to the thread typed in; echoes are tracked so the view keeps typing.
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
    model.setAskAssistant(SHARED, true)
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

    // Card events go to Rust; only a matching effect can reveal source, never a late effect for a different thread.
    val evidence =
        JSONObject(
            """{"id":"evidence","kind":"tool","body":"","author_name":"Pip","inserted_at":"2026-10-22T12:00:00Z","tool_status":"succeeded","component":{"type":"result_table","version":1,"data":{"title":"Accounts","columns":["Name"],"rows":[["Northstar"]]},"actions":[{"id":"show_evidence","label":"View source"}],"fallback":"Northstar"}}""",
        )
    model.refresh()
    take("request", "refresh").second(Result.success(snapshot(21, SHARED).put("messages", org.json.JSONArray().put(evidence))))
    model.componentAction("evidence", "show_evidence")
    val event = take("component_action")
    check(event.first.getString("id") == SHARED && event.first.getString("message_id") == "evidence")
    val effect = JSONObject().put("effect", "show_evidence").put("thread_id", SHARED).put("message_id", "evidence")
    event.second(Result.success(effect))
    check(model.revealedEvidence == setOf("evidence"))
    model.componentAction("evidence", "show_evidence")
    val lateEffect = take("component_action")
    model.select(PRIVATE)
    take("request", "select").second(Result.success(snapshot(22, PRIVATE)))
    lateEffect.second(Result.success(effect))
    check(model.revealedEvidence.isEmpty())

    // Closing releases the handle and ignores late results.
    model.close()
    check(take("close").first.getString("connection") == "handle")
    pending.toList().forEach { it.second(Result.success(snapshot(99, PRIVATE))) }
    check(model.snapshot.sequence == 0L && model.snapshot.threads.isEmpty())

    // A handle that opens after close is released immediately.
    val late = AtlasOrbitModel { action, done -> pending.add(action to done) }
    late.open()
    late.close()
    take("open").second(Result.success(JSONObject("""{"connection":"late"}""")))
    check(take("close").first.getString("connection") == "late")

    // Cold notification links select by UUID without waiting for a list or inventing thread metadata.
    pending.clear()
    val cold = AtlasOrbitModel { action, done -> pending.add(action to done) }
    val unseen = "01922cc0-0000-7000-8000-000000000099"
    cold.select(PRIVATE)
    cold.select(unseen)
    check(cold.canBack && cold.selectionId == unseen && cold.snapshot.selected == null)
    take("open").second(Result.success(JSONObject().put("connection", "cold")))
    val direct = take("request", "select")
    check(direct.first.getJSONObject("command").getString("id") == unseen)
    check(pending.none { it.first.optJSONObject("command")?.optString("action") == "select" })
    direct.second(
        Result.success(
            snapshot(1)
                .put("selection_id", unseen)
                .put("error", "This thread is unavailable or you no longer have access."),
        ),
    )
    check(cold.canBack && cold.snapshot.selected == null && cold.selectionId == unseen)
    cold.refresh()
    take("request", "refresh").second(Result.success(snapshot(2, unseen).put("selection_id", unseen)))
    check(cold.snapshot.selected?.id == unseen)
    cold.showList()
    val leave = take("request", "leave")
    check(leave.first.getJSONObject("command").getString("id") == unseen)
    leave.second(Result.success(snapshot(3).put("has_drafts", true)))
    check(!cold.canBack && cold.hasProtectedWork) // Retained drafts protect links even from the list.
    cold.close()
    take("close")

    // Back before the connection opens cancels the queued intent rather than navigating later.
    pending.clear()
    val cancelled = AtlasOrbitModel { action, done -> pending.add(action to done) }
    cancelled.select(unseen)
    check(cancelled.back() && !cancelled.canBack)
    take("open").second(Result.success(JSONObject().put("connection", "cancelled")))
    check(pending.none { it.first.optJSONObject("command")?.optString("action") == "select" })
    cancelled.close()
    take("close")

    // Prompt navigation loads earlier history through the retained model, without editing or sending.
    for (id in listOf(PRIVATE, SHARED)) {
        pending.clear()
        val history = AtlasOrbitModel { action, done -> pending.add(action to done) }
        history.open()
        take("open").second(Result.success(JSONObject().put("connection", "history")))
        val recent =
            JSONObject()
                .put("id", "recent")
                .put("kind", "human")
                .put("body", "Recent prompt")
                .put("inserted_at", "2026-10-24T12:00:00Z")
        val earlier =
            JSONObject()
                .put("id", "earlier")
                .put("kind", "human")
                .put("body", "Earlier prompt")
                .put("inserted_at", "2026-10-24T11:00:00Z")
        val chips =
            org.json.JSONArray().put(
                JSONObject()
                    .put("id", "pending-file")
                    .put("filename", "notes.txt")
                    .put("content_type", "text/plain")
                    .put("byte_size", 5),
            )
        val loaded =
            snapshot(1, id, "Unsent draft")
                .put("has_older", true)
                .put("messages", org.json.JSONArray().put(recent))
                .put("draft_attachments", chips)
        take("request", "load").second(Result.success(loaded))
        history.loadOlder()
        val older = take("request", "history")
        check(older.first.getJSONObject("command").getBoolean("older"))
        check(history.selectionId == id && history.snapshot.draft == "Unsent draft")
        older.second(Result.failure(IllegalStateException("Offline")))
        check(
            history.failure == "Offline" && history.snapshot.messages
                .single()
                .id == "recent",
        )
        check(
            history.snapshot.draftAttachments
                .single()
                .filename == "notes.txt" && history.hasProtectedWork,
        )

        history.loadOlder()
        take("request", "history").second(
            Result.success(
                snapshot(2, id, "Unsent draft")
                    .put("draft_attachments", chips)
                    .put(
                        "messages",
                        org.json
                            .JSONArray()
                            .put(earlier)
                            .put(recent),
                    ),
            ),
        )
        check(history.snapshot.messages.map { it.id } == listOf("earlier", "recent") && !history.snapshot.hasOlder)
        check(history.selectionId == id && history.snapshot.draft == "Unsent draft" && history.failure == null)
        check(
            history.snapshot.draftAttachments
                .single()
                .filename == "notes.txt",
        )
        check(pending.isEmpty()) // No draft, send, select, leave, or rollback request was emitted.
        history.close()
        take("close")
    }
    checkOrbitAttachments()
}

private fun checkOrbitAttachments() {
    val pending = mutableListOf<Pair<JSONObject, (Result<JSONObject>) -> Unit>>()
    val model = AtlasOrbitModel { action, done -> pending.add(action to done) }

    fun take(action: String): Pair<JSONObject, (Result<JSONObject>) -> Unit> {
        val index =
            pending.indexOfFirst {
                it.first.optJSONObject("command")?.optString("action") == action ||
                    it.first.optString("action") == action
            }
        check(index >= 0) { "missing attachment action $action" }
        return pending.removeAt(index)
    }

    fun snapshot(
        sequence: Int,
        attachments: org.json.JSONArray = org.json.JSONArray(),
    ) = JSONObject(
        """{"sequence":$sequence,"threads":[],"selected":{"id":"$PRIVATE","title":"Pip","kind":"private","status":"active","participants":[],"updated_at":"2026-10-24T00:00:00Z"},"selection_id":"$PRIVATE","messages":[],"people":[],"draft":"","draft_attachments":$attachments,"has_drafts":${attachments.length() > 0}}""",
    )
    val file = JSONObject("""{"id":"$SHARED","filename":"report.txt","content_type":"text/plain","byte_size":5}""")
    model.setActive(true)
    take("open").second(Result.success(JSONObject().put("connection", "attachments")))
    take("active")
    take("load").second(Result.success(snapshot(1)))
    check(model.beginPick() == PRIVATE && model.hasProtectedWork)
    model.finishPick(
        PRIVATE,
        Result.success(
            dev.tuist.atlas.AtlasOrbitAttachments
                .Picked("report.txt", "text/plain", "aGVsbG8="),
        ),
    )
    val upload = take("upload_attachment")
    check(upload.first.getJSONObject("command").getString("data") == "aGVsbG8=")
    check(!upload.first.getJSONObject("command").has("client_id")) // Rust, not Kotlin, owns retry identity.
    check(model.beginPick() == null)
    upload.second(Result.success(snapshot(2).put("upload_pending", true).put("upload_filename", "report.txt").put("has_drafts", true)))
    model.send(PRIVATE, "Wait for the upload")
    check(pending.none { it.first.optJSONObject("command")?.optString("action") == "send" })
    model.retryUpload()
    val retry = take("retry_upload")
    check(!retry.first.getJSONObject("command").has("data"))
    retry.second(Result.success(snapshot(3, org.json.JSONArray().put(file))))
    model.send(PRIVATE, "")
    val send = take("send")
    check(
        send.first
            .getJSONObject("command")
            .getJSONArray("attachment_ids")
            .getString(0) == SHARED,
    )
    send.second(Result.success(snapshot(4, org.json.JSONArray().put(file)).put("error", "Try again.")))
    check(
        model.snapshot.draftAttachments
            .single()
            .id == SHARED && model.hasProtectedWork,
    )
    var downloaded = false
    model.downloadAttachment(SHARED) { downloaded = true }
    val download = take("download_attachment")
    model.setActive(false)
    download.second(
        Result.success(JSONObject().put("thread_id", PRIVATE).put("attachment", JSONObject(file.toString()).put("data", "aGVsbG8="))),
    )
    check(!downloaded) // A result from a previous foreground period must not expose bytes.
    model.setActive(true)
    take("active")
    model.downloadAttachment(SHARED) {
        check(it.getOrThrow().getString("data") == "aGVsbG8=")
        downloaded = true
    }
    take(
        "download_attachment",
    ).second(Result.success(JSONObject().put("thread_id", PRIVATE).put("attachment", JSONObject(file.toString()).put("data", "aGVsbG8="))))
    check(downloaded)
    model.removeAttachment(SHARED)
    take("delete_attachment").second(Result.success(snapshot(5)))
    check(model.snapshot.draftAttachments.isEmpty())

    fun tool(
        id: String,
        parent: String? = null,
    ) = JSONObject(
        """{"id":"$id","kind":"tool","body":"original evidence","author_name":"Pip","inserted_at":"2026-10-24T00:00:00Z","tool_status":"succeeded","tool_name":"research"}""",
    ).put("parent_message_id", parent ?: JSONObject.NULL)
    val orphan = "00000000-0000-4000-8000-000000000003"
    val missing = "00000000-0000-4000-8000-000000000004"
    model.refresh()
    take(
        "refresh",
    ).second(
        Result.success(
            snapshot(6).put(
                "messages",
                org.json
                    .JSONArray()
                    .put(tool(PRIVATE))
                    .put(tool(SHARED, PRIVATE))
                    .put(tool(orphan, missing)),
            ),
        ),
    )
    check(model.childTools(PRIVATE).single().id == SHARED)
    check(model.timeline().flatten().map { it.id } == listOf(PRIVATE, orphan))
    check(
        model
            .timeline()
            .flatten()
            .flatMap { listOf(it.id) + model.childTools(it.id).map { child -> child.id } }
            .toSet() ==
            setOf(PRIVATE, SHARED, orphan),
    )
    model.toggleToolGroup(PRIVATE)
    check(PRIVATE in model.expandedToolGroups)
    // Off-page, cyclic, and malformed parents leave evidence inspectable at the root.
    model.refresh()
    take(
        "refresh",
    ).second(
        Result.success(
            snapshot(
                7,
            ).put(
                "messages",
                org.json
                    .JSONArray()
                    .put(tool(PRIVATE, SHARED))
                    .put(tool(SHARED, PRIVATE))
                    .put(tool(orphan, "not-a-uuid")),
            ),
        ),
    )
    check(model.timeline().flatten().size == 3 && model.childTools(PRIVATE).isEmpty())
    model.close()

    val boundary = dev.tuist.atlas.AtlasOrbitAttachments
    boundary.validate("report.txt", "text/plain", 5)
    for (name in listOf("../report", "a\\b", "\u202ereport", "a\n.txt", "")) {
        check(
            runCatching {
                boundary.validate(name, "text/plain", 5)
            }.isFailure,
        )
    }
    check(runCatching { boundary.validate("report.txt", "text/plain\n", 5) }.isFailure)
    check(runCatching { boundary.validate("report.txt", "text/plain", boundary.MAX_BYTES.toLong() + 1) }.isFailure)
    check(boundary.readBounded(java.io.ByteArrayInputStream(ByteArray(boundary.MAX_BYTES))).size == boundary.MAX_BYTES)
    check(runCatching { boundary.readBounded(java.io.ByteArrayInputStream(ByteArray(boundary.MAX_BYTES + 1))) }.isFailure)
    check(runCatching { boundary.readBounded(java.io.ByteArrayInputStream(byteArrayOf())) }.isFailure)
}
