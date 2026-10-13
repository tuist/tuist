package dev.tuist.atlas

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)

        val content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val padding = (24 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding, padding, padding)
            }
        content.addView(
            TextView(this).apply {
                text = getString(R.string.welcome)
                textSize = 28f
                setPadding(0, 0, 0, 24)
                if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
            },
        )
        content.addView(
            TextView(this).apply {
                text = getString(R.string.sign_in_hint)
                setPadding(0, 0, 0, 32)
            },
        )
        AtlasCore().sections().forEach { section ->
            content.addView(
                Button(this).apply {
                    text = section.title
                    contentDescription = "${section.title}. ${section.description}"
                    setOnClickListener { openSection(section) }
                },
            )
            content.addView(
                TextView(this).apply {
                    text = section.description
                    textSize = 16f
                    setPadding(0, 0, 0, 32)
                },
            )
        }
        setContentView(
            ScrollView(this).apply {
                setOnApplyWindowInsetsListener { view, insets ->
                    view.setPadding(
                        insets.systemWindowInsetLeft,
                        insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight,
                        insets.systemWindowInsetBottom,
                    )
                    insets
                }
                addView(
                    content,
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            },
        )
    }

    private fun openSection(section: AtlasSection) {
        val uri = Uri.parse(section.url)
        check(uri.scheme == "https" && uri.host == "atlas.tuist.dev")
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, uri).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                },
            )
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, R.string.no_browser, Toast.LENGTH_LONG).show()
        }
    }
}
