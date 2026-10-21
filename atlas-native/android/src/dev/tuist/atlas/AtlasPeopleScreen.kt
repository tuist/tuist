package dev.tuist.atlas

import android.app.Activity
import android.graphics.Typeface
import android.os.Build
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toolbar

class AtlasPeopleScreen(
    private val activity: Activity,
    private val model: AtlasPresenceModel,
) {
    val toolbar = Toolbar(activity).apply { title = "People" }
    private val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val listener: () -> Unit = { render() }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(toolbar, LinearLayout.LayoutParams(-1, -2))
            addView(ScrollView(activity).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
            setOnApplyWindowInsetsListener { root, insets ->
                root.setPadding(
                    insets.systemWindowInsetLeft,
                    insets.systemWindowInsetTop,
                    insets.systemWindowInsetRight,
                    insets.systemWindowInsetBottom,
                )
                insets
            }
        }

    init {
        model.listener = listener
        model.show("people")
        render()
    }

    fun close() {
        if (model.listener === listener) model.listener = null
    }

    private fun render() {
        content.removeAllViews()
        text("Your team, here in Atlas", true)
        text("Availability updates while Atlas is active. It does not mean someone is editing.")
        val names = model.people.filter { it.here }.joinToString(", ") { it.name }
        if (names.isNotEmpty()) text("Also here: $names")
        model.people.forEach { person ->
            text(person.name, true)
            text("${person.email}\n${if (person.online) "● Online" else "○ Offline"}")
        }
        model.error?.let { text(it) }
        if (model.people.isEmpty() && model.error == null) text("Loading people…")
    }

    private fun text(
        value: String,
        heading: Boolean = false,
    ) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = if (heading) 18f else 15f
                if (heading) typeface = Typeface.DEFAULT_BOLD
                val padding = (16 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding / 2, padding, padding / 2)
                minHeight = (48 * resources.displayMetrics.density).toInt()
                if (heading && Build.VERSION.SDK_INT >= 28) accessibilityHeading = true
            },
            LinearLayout.LayoutParams(-1, -2),
        )
    }
}
