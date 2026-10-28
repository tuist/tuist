package dev.tuist.atlas

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView

class AtlasLoginView(
    context: Context,
    busy: Boolean,
    error: String?,
    hosted: () -> Unit,
    selfHosted: () -> Unit,
) : FrameLayout(context) {
    private val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val accent = Color.rgb(8, 124, 170)
    private val label = if (dark) Color.rgb(253, 253, 253) else Color.rgb(23, 26, 28)
    private val tertiaryLabel = if (dark) Color.rgb(105, 108, 114) else Color.rgb(157, 166, 175)

    init {
        addView(
            ImageView(context).apply {
                setImageResource(R.drawable.atlas_login_background)
                scaleType = ImageView.ScaleType.CENTER_CROP
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            },
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        val hero =
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                minimumHeight = dp(320)
                setPadding(dp(24), dp(32), dp(24), dp(80))
            }
        hero.addView(
            ImageView(context).apply {
                setImageResource(R.drawable.atlas_mark)
                setPadding(dp(12), dp(12), dp(12), dp(12))
                background =
                    GradientDrawable().apply {
                        setColor(accent)
                        cornerRadius = dp(12).toFloat()
                    }
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            },
            LinearLayout.LayoutParams(dp(60), dp(60)).apply { bottomMargin = dp(32) },
        )
        hero.addView(
            text(R.string.login_title, 28f).apply {
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                setPadding(0, 0, 0, dp(12))
                if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
            },
        )
        hero.addView(text(R.string.login_subtitle, 14f))
        content.addView(hero, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, 1f))

        val panel =
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(24), dp(32), dp(24), dp(12))
                background =
                    GradientDrawable().apply {
                        setColor(if (dark) Color.argb(204, 14, 14, 14) else Color.argb(153, 255, 255, 255))
                        cornerRadii = floatArrayOf(dp(32).toFloat(), dp(32).toFloat(), dp(32).toFloat(), dp(32).toFloat(), 0f, 0f, 0f, 0f)
                        setStroke(dp(2), if (dark) Color.rgb(31, 31, 31) else Color.WHITE)
                    }
            }
        if (busy) {
            panel.addView(ProgressBar(context), LinearLayout.LayoutParams(dp(24), dp(24)).apply { gravity = Gravity.CENTER })
            panel.addView(text(R.string.signing_in, 12f))
        }
        error?.let { message ->
            panel.addView(
                textView(12f).apply {
                    text = message
                    setTextColor(if (dark) Color.rgb(255, 150, 150) else Color.rgb(175, 25, 35))
                    accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                    setPadding(0, 0, 0, dp(12))
                },
            )
        }
        panel.addView(signInButton(R.string.sign_in, true, !busy, hosted))
        panel.addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(12), 0, dp(12))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                addView(line(), LinearLayout.LayoutParams(0, dp(1), 1f))
                addView(
                    text(R.string.login_or, 12f).apply {
                        setTextColor(tertiaryLabel)
                        setPadding(dp(8), 0, dp(8), 0)
                    },
                )
                addView(line(), LinearLayout.LayoutParams(0, dp(1), 1f))
            },
        )
        panel.addView(signInButton(R.string.self_hosted, false, !busy, selfHosted))
        content.addView(panel, LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        val scroll =
            ScrollView(context).apply {
                isFillViewport = true
                addView(content, ViewGroup.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
            }
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        setOnApplyWindowInsetsListener { _, insets ->
            scroll.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
            panel.setPadding(dp(24), dp(32), dp(24), dp(12) + insets.systemWindowInsetBottom)
            insets
        }
    }

    private fun signInButton(
        title: Int,
        primary: Boolean,
        enabled: Boolean,
        action: () -> Unit,
    ): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            minimumHeight = dp(48)
            setPadding(dp(12), dp(12), dp(12), dp(12))
            isEnabled = enabled
            alpha = if (enabled) 1f else 0.55f
            isClickable = true
            isFocusable = true
            contentDescription = context.getString(title)
            accessibilityDelegate =
                object : AccessibilityDelegate() {
                    override fun onInitializeAccessibilityNodeInfo(
                        host: View,
                        info: AccessibilityNodeInfo,
                    ) {
                        super.onInitializeAccessibilityNodeInfo(host, info)
                        info.className = Button::class.java.name
                    }
                }
            val foreground = if (primary) Color.WHITE else label
            val base =
                if (primary) {
                    accent
                } else if (dark) {
                    Color.rgb(31, 33, 38)
                } else {
                    Color.rgb(253, 253, 253)
                }
            background =
                RippleDrawable(
                    ColorStateList.valueOf(if (primary) 0x33FFFFFF else 0x22000000),
                    GradientDrawable(
                        GradientDrawable.Orientation.TOP_BOTTOM,
                        intArrayOf(if (primary) Color.rgb(48, 145, 184) else base, base),
                    ).apply {
                        cornerRadius = dp(8).toFloat()
                        setStroke(dp(1), if (primary) Color.rgb(6, 97, 133) else 0x14000000)
                    },
                    null,
                )
            elevation = dp(2).toFloat()
            addView(
                ImageView(context).apply {
                    setImageResource(if (primary) R.drawable.atlas_mark else R.drawable.atlas_server)
                    imageTintList = ColorStateList.valueOf(foreground)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
                LinearLayout.LayoutParams(dp(20), dp(20)).apply { marginEnd = dp(6) },
            )
            addView(
                text(title, 16f).apply {
                    setTextColor(foreground)
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
                },
            )
            setOnClickListener { if (isEnabled) action() }
        }

    private fun text(
        title: Int,
        size: Float,
    ): TextView = textView(size).apply { setText(title) }

    private fun textView(size: Float): TextView =
        TextView(context).apply {
            textSize = size
            gravity = Gravity.CENTER
            setTextColor(label)
        }

    private fun line(): View = View(context).apply { setBackgroundColor((tertiaryLabel and 0x00FFFFFF) or 0x4D000000) }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
