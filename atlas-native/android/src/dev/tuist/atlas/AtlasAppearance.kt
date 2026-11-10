package dev.tuist.atlas

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.CompoundButton
import android.widget.EditText
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toolbar
import org.json.JSONObject
import java.util.concurrent.Executors

class AtlasAppearance(
    context: Context,
) {
    private val context = context.applicationContext
    private val preferences = context.getSharedPreferences("atlas.appearance", Context.MODE_PRIVATE)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var generation = 0
    private var refreshedAt = 0L
    private var loading = false
    private var version = 0
    var listener: (() -> Unit)? = null
    var showingSettings = false
    var server: String? = null
        private set
    var catalog: JSONObject? = null
        private set
    var selection = "server-default"
        private set
    var mode = "system"
        private set

    val themes: List<JSONObject>
        get() = catalog?.getJSONArray("themes")?.let { array -> (0 until array.length()).map { array.getJSONObject(it) } } ?: emptyList()
    val activeSelection: String
        get() = if (themes.any { it.getString("id") == selection }) selection else "server-default"
    val theme: JSONObject?
        get() =
            themes.firstOrNull { it.getString("id") == activeSelection }
                ?: themes.firstOrNull { it.getString("id") == catalog?.getString("default_theme_id") }
    val dark: Boolean
        get() =
            when (mode) {
                "dark" -> true
                "light" -> false
                else -> context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
            }
    val palette: JSONObject?
        get() = theme?.getJSONObject(if (dark) "dark" else "light")

    fun configure(nextServer: String?) {
        if (server == nextServer && (catalog != null || loading)) {
            refresh()
            return
        }
        showingSettings = false
        server = nextServer
        generation += 1
        val identity = generation
        catalog = null
        refreshedAt = 0
        loading = true
        selection = nextServer?.let { preferences.getString("$it.theme", "server-default") } ?: "server-default"
        mode = nextServer?.let { preferences.getString("$it.mode", "system") }?.takeIf { it in modes } ?: "system"
        changed()
        val cached = nextServer?.let { preferences.getString("$it.catalog", null) }
        worker.execute {
            val defaults = runCatching { command(JSONObject().put("operation", "default_themes")) }.getOrNull()
            val saved =
                cached?.takeIf { it.length <= 65_536 }?.let {
                    runCatching { command(JSONObject().put("operation", "validate_themes").put("catalog", JSONObject(it))) }.getOrNull()
                }
            main.post {
                if (identity == generation) {
                    catalog = saved ?: defaults
                    loading = false
                    changed()
                    refresh()
                }
            }
        }
    }

    fun refresh() {
        val origin = server ?: return
        if (loading || System.nanoTime() - refreshedAt < 300_000_000_000L && refreshedAt != 0L) return
        loading = true
        val identity = generation
        worker.execute {
            val result = runCatching { command(JSONObject().put("operation", "themes").put("server", origin)) }.getOrNull()
            main.post {
                if (identity == generation) {
                    loading = false
                    refreshedAt = System.nanoTime()
                    if (result != null) {
                        catalog = result
                        preferences.edit().putString("$origin.catalog", result.toString()).apply()
                        changed()
                    }
                }
            }
        }
    }

    fun chooseTheme(id: String) {
        val origin = server ?: return
        if (id != "server-default" && themes.none { it.getString("id") == id }) return
        selection = id
        preferences.edit().putString("$origin.theme", id).apply()
        changed()
    }

    fun chooseMode(value: String) {
        val origin = server ?: return
        if (value !in modes) return
        mode = value
        preferences.edit().putString("$origin.mode", value).apply()
        changed()
    }

    fun close() {
        generation += 1
        listener = null
        worker.shutdown()
    }

    private fun changed() {
        version += 1
        listener?.invoke()
    }

    private fun command(request: JSONObject): JSONObject {
        val result = JSONObject(AtlasAuth.execute(request.toString()))
        return result.getJSONObject("ok")
    }

    @Suppress("DEPRECATION")
    fun apply(
        activity: Activity,
        root: View,
    ) {
        val palette = palette.takeIf { server != null }
        val highContrast = Settings.Secure.getInt(context.contentResolver, "high_text_contrast_enabled", 0) == 1
        val colors =
            if (highContrast && palette != null) {
                JSONObject(palette.toString()).apply {
                    put("text", if (dark) "#FFFFFF" else "#000000")
                    put("secondary_text", if (dark) "#FFFFFF" else "#000000")
                    put("background", if (dark) "#000000" else "#FFFFFF")
                    put("surface", if (dark) "#000000" else "#FFFFFF")
                }
            } else {
                palette
            }
        if (colors != null) {
            root.setBackgroundColor(color(colors, "background"))
            paint(root, colors, "$version:$dark:$highContrast")
        }
        val background = colors?.let { color(it, "background") } ?: Color.parseColor(if (dark) "#303030" else "#F5FAFF")
        activity.window.statusBarColor = background
        activity.window.navigationBarColor = if (Build.VERSION.SDK_INT >= 27 || dark) background else Color.BLACK
        var flags = activity.window.decorView.systemUiVisibility
        flags = if (dark) flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv() else flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        if (Build.VERSION.SDK_INT >= 27) {
            flags =
                if (dark) flags and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv() else flags or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
        activity.window.decorView.systemUiVisibility = flags
    }

    private fun paint(
        view: View,
        colors: JSONObject,
        signature: String,
    ) {
        if (view.getTag(R.id.atlas_theme_revision) != signature) {
            view.setTag(R.id.atlas_theme_revision, signature)
            val tint = color(colors, "tint")
            when (view) {
                is Toolbar -> {
                    view.setBackgroundColor(color(colors, "surface"))
                    view.setTitleTextColor(color(colors, "text"))
                    view.setSubtitleTextColor(color(colors, "secondary_text"))
                    view.navigationIcon?.mutate()?.setTint(tint)
                    view.overflowIcon?.mutate()?.setTint(tint)
                    for (index in 0 until view.menu.size()) {
                        view.menu
                            .getItem(index)
                            .icon
                            ?.mutate()
                            ?.setTint(tint)
                    }
                }
                is AtlasInvoiceChart -> view.setTheme(color(colors, "text"), color(colors, "accent"))
                is CompoundButton -> {
                    view.setTextColor(color(colors, "text"))
                    view.buttonTintList =
                        ColorStateList(
                            arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                            intArrayOf(tint, color(colors, "secondary_text")),
                        )
                }
                is Button -> {
                    if (view.getTag(R.id.atlas_primary_action) == true) {
                        view.setTextColor(states(color(colors, "on_accent")))
                        view.background =
                            RippleDrawable(
                                ColorStateList.valueOf(color(colors, "on_accent") and 0x33FFFFFF),
                                GradientDrawable().apply {
                                    setColor(states(color(colors, "accent")))
                                    cornerRadius =
                                        (theme?.getDouble("button_radius") ?: 8.0).toFloat() * view.resources.displayMetrics.density
                                },
                                null,
                            )
                    } else {
                        view.setTextColor(states(tint))
                    }
                }
                is EditText -> {
                    view.setTextColor(color(colors, "text"))
                    view.setHintTextColor(color(colors, "secondary_text"))
                    view.backgroundTintList = states(tint)
                }
                is TextView -> {
                    view.setTextColor(color(colors, if (view.id == android.R.id.text2) "secondary_text" else "text"))
                    if (Build.VERSION.SDK_INT >= 28 && view.isAccessibilityHeading) {
                        view.typeface =
                            Typeface.create(
                                if (theme?.getString("typography") == "rounded") "sans-serif-rounded" else "sans-serif",
                                if (theme?.getString("typography") == "strong") Typeface.BOLD else Typeface.NORMAL,
                            )
                    }
                }
                is ProgressBar -> view.indeterminateTintList = ColorStateList.valueOf(tint)
            }
        }
        if (view is ViewGroup) for (index in 0 until view.childCount) paint(view.getChildAt(index), colors, signature)
    }

    private fun states(color: Int) =
        ColorStateList(
            arrayOf(intArrayOf(-android.R.attr.state_enabled), intArrayOf()),
            intArrayOf((color and 0x00FFFFFF) or 0x61000000, color),
        )

    companion object {
        val modes = listOf("system", "light", "dark")

        fun color(
            palette: JSONObject,
            key: String,
        ): Int = Color.parseColor(palette.getString(key))
    }
}
