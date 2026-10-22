package dev.tuist.atlas

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.longbridge.nsh.NshComponent
import com.longbridge.nsh.NshView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID
import kotlin.math.ceil

// Presentation only: card content and actions arrive from the server through Rust.
class AtlasConversationCardView(
    context: Context,
    private val card: JSONObject,
    private val appearance: AtlasAppearance?,
    private val action: (String) -> Unit,
) : FrameLayout(context) {
    private var engine: NshView? = null
    private var directory: File? = null
    private var failed = false
    private var ready = false
    private val timeout = Runnable { if (!ready) fallback() }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (engine == null) {
            if (failed || Build.VERSION.SDK_INT < 28) fallback() else start()
        }
    }

    override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
    }

    private fun stop() {
        removeCallbacks(timeout)
        engine?.destroy()
        engine = null
        removeAllViews()
        directory?.deleteRecursively()
        directory = null
    }

    private fun fallback() {
        if (!isAttachedToWindow) return
        stop()
        failed = true
        val item = card.getJSONArray("actions").getJSONObject(0)
        addView(
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(
                    TextView(context).apply {
                        text = card.getString("fallback")
                        textSize = 15f
                        setTextIsSelectable(true)
                    },
                )
                addView(
                    Button(context).apply {
                        text = item.getString("label")
                        isAllCaps = false
                        minHeight = dp(48)
                        setOnClickListener { action(item.getString("id")) }
                    },
                )
            },
            LayoutParams(-1, -2),
        )
        layoutParams?.let {
            it.height = -2
            layoutParams = it
        }
    }

    private fun start() {
        ready = false
        try {
            val runtime = NshView(context)
            engine = runtime
            runtime.setLimits(16, 0, 1000, 250, 512)
            check(runtime.setGrantedCapabilities("{}"))
            val storage = File(context.cacheDir, "atlas-card-${UUID.randomUUID()}").also { check(it.mkdirs()) }
            directory = storage
            runtime.setStorageDirectory(File(storage, "storage"))
            runtime.setErrorListener { post { if (engine === runtime) fallback() } }
            val payload = mapOf("card" to jsonValue(card), "colors" to colors())
            runtime.registerComponent("atlas.conversation-card") { bridge ->
                object : NshComponent {
                    private val empty = View(context)

                    override fun view(): View = empty

                    override fun setProp(
                        name: String,
                        value: Any?,
                    ) {
                        if (name == "ready") bridge.emit("data", payload)
                    }

                    override fun command(
                        name: String,
                        args: Any?,
                    ) {
                        when (name) {
                            "action" -> if (args is String) action(args)
                            "height" -> resize(args)
                        }
                    }
                }
            }
            addView(runtime, LayoutParams(-1, -1))
            layoutParams?.let {
                it.height = dp(180)
                layoutParams = it
            }
            for (name in listOf("bundle.js", "capabilities.json", "app.json")) {
                context.assets.open("nsh/$name").use { input -> File(storage, name).outputStream().use { input.copyTo(it) } }
            }
            check(runtime.loadBundleFile(File(storage, "bundle.js")))
            postDelayed(timeout, 3000)
        } catch (_: Exception) {
            post { fallback() }
        }
    }

    private fun resize(value: Any?) {
        val height = (value as? Number)?.toDouble()
        if (height == 0.0) return
        if (height == null || !height.isFinite() || height !in 1.0..6000.0) {
            post { fallback() }
            return
        }
        ready = true
        removeCallbacks(timeout)
        val pixels = ceil(height * resources.displayMetrics.density).toInt()
        layoutParams?.let {
            if (it.height != pixels) {
                it.height = pixels
                layoutParams = it
            }
        }
    }

    private fun colors(): Map<String, String> {
        val dark =
            appearance?.dark ?: (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
        val palette = appearance?.palette
        return mapOf(
            "text" to (palette?.optString("text") ?: if (dark) "#FFFFFF" else "#171717"),
            "secondary" to (palette?.optString("secondary_text") ?: if (dark) "#B4B4B4" else "#595959"),
            "surface" to (palette?.optString("surface") ?: if (dark) "#242424" else "#FFFFFF"),
            "accent" to (palette?.optString("accent") ?: if (dark) "#82B1FF" else "#0057B8"),
        )
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun jsonValue(value: Any?): Any? =
        when (value) {
            is JSONObject -> value.keys().asSequence().associateWith { jsonValue(value.get(it)) }
            is JSONArray -> List(value.length()) { jsonValue(value.get(it)) }
            JSONObject.NULL -> null
            else -> value
        }
}
