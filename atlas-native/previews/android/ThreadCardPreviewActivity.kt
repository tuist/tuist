package dev.tuist.atlas.preview

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import dev.tuist.atlas.AtlasOrbitModel
import dev.tuist.atlas.AtlasOrbitScreen
import dev.tuist.atlas.AtlasPresenceModel
import dev.tuist.atlas.AtlasThreadCardView
import dev.tuist.atlas.AuthFailure
import org.json.JSONArray
import org.json.JSONObject

class ThreadCardPreviewActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkOrbitModel()
        if (intent.getBooleanExtra("signals", false)) {
            showSignals()
            return
        }
        if (intent.getBooleanExtra("saved-inbox", false)) {
            showInbox()
            return
        }
        val evidence = TextView(this).apply { textSize = 16f }
        val card =
            JSONObject(
                """{"type":"result_table","version":1,"data":{"title":"Query comparison","columns":["Finding","Impact"],"rows":[["The new filter bypasses the existing index.","2.4× slower"]]},"actions":[{"id":"show_evidence","label":"View source"}],"fallback":"The new filter bypasses the existing index."}""",
            )
        val content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val padding = (16 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding, padding, padding)
                addView(
                    TextView(context).apply {
                        text = "Thread card · offline fixture"
                        textSize = 18f
                    },
                )
                addView(
                    AtlasThreadCardView(context, card, null) { event ->
                        check(event == "show_evidence")
                        evidence.text = "Original source evidence"
                    },
                    LinearLayout.LayoutParams(-1, (180 * resources.displayMetrics.density).toInt()),
                )
                addView(evidence)
            }
        setContentView(
            ScrollView(this).apply {
                fitsSystemWindows = true
                addView(content)
            },
        )
    }

    private fun showInbox() {
        val saved =
            JSONObject(
                """{"sequence":1,"cached":true,"assistant":{"name":"Pip","configured":true},
            "threads":[{"id":"01922cc0-0000-7000-8000-000000000001","title":"Release checklist","kind":"shared","status":"active",
            "summary":"Check the release notes before tomorrow’s rollout.","participants":[],"updated_at":"2026-10-27T10:00:00Z"}],
            "messages":[],"people":[]}""",
            )
        val refreshed = intent.getBooleanExtra("refreshed", false)
        var failedRefresh = false
        val model =
            AtlasOrbitModel { action, done ->
                if (action.optString("action") == "open") {
                    done(Result.success(JSONObject().put("connection", "preview-only").put("snapshot", saved)))
                } else if (refreshed || failedRefresh) {
                    done(Result.success(JSONObject(saved.toString()).put("sequence", 2).put("cached", false)))
                } else {
                    Handler(Looper.getMainLooper()).postDelayed({
                        failedRefresh = true
                        done(Result.failure(AuthFailure("network", "Could not connect securely to Atlas. Try again.")))
                    }, 6000)
                }
            }
        val screen = AtlasOrbitScreen(this, "Orbit", model, null, {})
        screen.view.fitsSystemWindows = true
        setContentView(screen.view)
        model.open()
    }

    private fun showSignals() {
        val threads = JSONArray()
        for ((index, priority) in listOf("now", "today", "later").withIndex()) {
            threads.put(
                JSONObject()
                    .put("id", "01922cc0-0000-7000-8000-00000000000${index + 1}")
                    .put("kind", if (index == 0 && intent.getBooleanExtra("environment", false)) "private" else "shared")
                    .put("status", "active")
                    .put("owner_id", "preview-self")
                    .put("origin", "signal")
                    .put("priority", priority)
                    .put("agent_status", if (index == 0) intent.getStringExtra("agent-status") else null)
                    .put("domain", if (index == 0) "engineering" else "commercial")
                    .put("title", listOf("Build listing errors", "Northstar asks about SSO", "New lead from Acme")[index])
                    .put(
                        "summary",
                        listOf(
                            "Error rate increased after the latest deployment.",
                            "Pip found the setup guide and drafted a response.",
                            "Review the company and suggest a first response.",
                        )[index],
                    ).put("participants", JSONArray("""[{"id":"preview-self","name":"Taylor"},{"id":"online","name":"Alex"}]"""))
                    .put("updated_at", "2026-10-28T10:00:00Z"),
            )
        }
        val messages = JSONArray()

        fun message(
            id: String,
            kind: String,
            body: String,
            notice: String? = null,
        ) {
            messages.put(
                JSONObject()
                    .put("id", id)
                    .put("kind", kind)
                    .put("body", body)
                    .put("notice_kind", notice)
                    .put("author_name", if (kind == "agent") "Pip" else "")
                    .put("inserted_at", "2026-10-28T10:00:00Z"),
            )
        }
        message("evidence", "system", "Error rate increased after the latest deployment. Pip is investigating.")
        message(
            "reply",
            "agent",
            "The increase is concentrated in build listing requests. Compare the new filter’s query plan before choosing a mitigation.",
        )
        message("join", "system", "Taylor joins the conversation.", "joined")
        message(
            "catch-up",
            "system",
            "Factual excerpts, not an AI-generated summary.\n\n" +
                "Initial request (excerpt):\nError rate increased after the latest deployment.\n\n" +
                "Latest Pip reply (excerpt):\nCompare the new filter’s query plan before choosing a mitigation.",
            "private_handoff",
        )
        var sequence = 0
        var selected: JSONObject? = null
        var draft = ""
        var status = "active"
        var query = ""
        var domain = ""

        fun snapshot() =
            JSONObject()
                .put("sequence", ++sequence)
                .put(
                    "assistant",
                    JSONObject()
                        .put("name", "Pip")
                        .put("configured", true)
                        .put("searchable", true)
                        .put(
                            "domains",
                            JSONArray()
                                .put(JSONObject().put("id", "engineering").put("name", "Engineering"))
                                .put(JSONObject().put("id", "commercial").put("name", "Commercial")),
                        ),
                ).put(
                    "threads",
                    JSONArray(
                        (0 until threads.length()).map { threads.getJSONObject(it) }.filter {
                            it.getString("status") == status &&
                                (domain.isEmpty() || it.optString("domain") == domain) &&
                                (it.optString("title") + " " + it.optString("summary")).contains(query, ignoreCase = true)
                        },
                    ),
                ).put("selected", selected ?: JSONObject.NULL)
                .put("selection_id", selected?.optString("id") ?: JSONObject.NULL)
                .put("messages", if (selected == null) JSONArray() else messages)
                .put("status_filter", status)
                .put("query", query)
                .put("domain_filter", domain)
                .put("draft", draft)
                .put("people", JSONArray())
        val model =
            AtlasOrbitModel { action, done ->
                if (action.optString("action") == "open") {
                    done(Result.success(JSONObject().put("connection", "signals-preview").put("snapshot", snapshot())))
                } else {
                    val command = action.optJSONObject("command") ?: action
                    when (command.optString("action")) {
                        "select" ->
                            selected =
                                (0 until threads.length()).map { threads.getJSONObject(it) }.first {
                                    it.getString("id") ==
                                        command.getString("id")
                                }
                        "leave" -> selected = null
                        "load" -> {
                            status = command.optString("status", status)
                            query = command.optString("query", query)
                            domain = command.optString("domain", domain)
                        }
                        "archive" -> selected?.put("status", if (command.getBoolean("archived")) "archived" else "active")
                        "draft" -> draft = command.optString("body")
                        "send" -> {
                            message("sent-$sequence", "human", command.optString("body"))
                            draft = ""
                        }
                    }
                    done(Result.success(snapshot()))
                }
            }
        val presence =
            AtlasPresenceModel { action, done ->
                when (action.optString("action")) {
                    "open" -> done(Result.success(JSONObject().put("connection", "signals-presence-preview")))
                    "next" ->
                        if (action.optLong("after") == 0L) {
                            done(Result.success(JSONObject("""{"sequence":1,"location":{},"people":[],"self_id":"preview-self"}""")))
                        }
                    else -> done(Result.success(JSONObject()))
                }
            }
        presence.setActive(true)
        val environments = AtlasEnvironmentFixtures()
        val screen =
            AtlasOrbitScreen(this, "Orbit", model, presence, {}, environmentRequest = { action, done ->
                done(runCatching { environments.execute(action) })
            })
        screen.view.fitsSystemWindows = true
        setContentView(screen.view)
        model.open()
        if (intent.getBooleanExtra("finish-activity", false)) {
            Handler(Looper.getMainLooper()).postDelayed({
                threads.getJSONObject(0).put("agent_status", "idle")
                model.refresh()
            }, 12_000)
        }
    }
}
