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
import dev.tuist.atlas.AtlasThreadCardView
import dev.tuist.atlas.AuthFailure
import org.json.JSONObject

class ThreadCardPreviewActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkOrbitModel()
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
}
