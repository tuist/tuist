package dev.tuist.atlas

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout

class AtlasHomeScreen(
    activity: Activity,
    content: View,
    titles: Map<String, String>,
    selected: String,
    choose: (String) -> Unit,
) {
    private val tabs =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            val columns = if (activity.resources.configuration.fontScale > 1.3f) 3 else 5
            titles.entries.toList().chunked(columns).forEach { entries ->
                val row = LinearLayout(activity)
                entries.forEach { (id, title) ->
                    row.addView(
                        Button(activity, null, android.R.attr.borderlessButtonStyle).apply {
                            text = title
                            textSize = 12f
                            isAllCaps = false
                            isSelected = id == selected
                            typeface =
                                android.graphics.Typeface.create(
                                    typeface,
                                    if (isSelected) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL,
                                )
                            minimumWidth = dp(activity, 48)
                            minWidth = dp(activity, 48)
                            minHeight = dp(activity, 64)
                            setPadding(dp(activity, 2), dp(activity, 8), dp(activity, 2), dp(activity, 8))
                            contentDescription = "$title tab${if (isSelected) ", selected" else ""}"
                            setOnClickListener { choose(id) }
                        },
                        LinearLayout.LayoutParams(0, -2, 1f),
                    )
                }
                addView(row, LinearLayout.LayoutParams(-1, -2))
            }
        }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(tabs, LinearLayout.LayoutParams(-1, -2))
            setOnApplyWindowInsetsListener { root, insets ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                    val bottom = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime()).bottom
                    root.setPadding(bars.left, bars.top, bars.right, bottom)
                    WindowInsets.CONSUMED
                } else {
                    root.setPadding(
                        insets.systemWindowInsetLeft,
                        insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight,
                        insets.systemWindowInsetBottom,
                    )
                    insets.consumeSystemWindowInsets()
                }
            }
        }

    fun fullScreen(value: Boolean) {
        tabs.visibility = if (value) View.GONE else View.VISIBLE
    }

    private fun dp(
        activity: Activity,
        value: Int,
    ) = (value * activity.resources.displayMetrics.density).toInt()
}
