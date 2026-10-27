package dev.tuist.atlas.preview

import android.app.Activity
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import dev.tuist.atlas.AtlasThreadCardView
import org.json.JSONObject

class ThreadCardPreviewActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkOrbitModel()
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
}
