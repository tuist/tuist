package dev.tuist.guild

import org.json.JSONObject
import java.util.concurrent.Executors

object AppCore {
    init {
        System.loadLibrary("tuist_app_core")
    }

    private external fun tabCount(): Int
    private external fun tabIdByte(index: Int, offset: Int): Int
    private external fun request(input: String, host: AppHost): String
    private external fun theme(): String

    // The Rust core's themes: Noora, the tokens the server's components use, then
    // Omarchy's palettes mapped to the same tokens.
    private val catalog: JSONObject by lazy { JSONObject(theme()) }
    private val themeList: List<JSONObject> by lazy {
        catalog.optJSONArray("themes")?.let { array -> (0 until array.length()).map { array.getJSONObject(it) } }.orEmpty()
    }

    val defaultTheme: String get() = catalog.optString("default", "noora")

    /** Every theme as (ID, name), in Profile's order. */
    val themes: List<Pair<String, String>> by lazy { themeList.map { it.optString("id") to it.optString("name") } }

    private fun entry(id: String): JSONObject? = themeList.firstOrNull { it.optString("id") == id } ?: themeList.firstOrNull()

    /** True or false when the theme has its own appearance, null when it follows the system. */
    fun themeAppearance(id: String): Boolean? = when (entry(id)?.optString("appearance")) {
        "dark" -> true
        "light" -> false
        else -> null
    }

    /** A Noora token's color in a theme for the appearance, as an opaque ARGB int. */
    fun color(themeId: String, name: String, dark: Boolean): Int {
        val hex = entry(themeId)?.optJSONObject(if (dark) "dark" else "light")?.optString(name).orEmpty()
        return 0xFF000000.toInt() or (hex.removePrefix("#").toIntOrNull(16) ?: 0)
    }

    // All engine and host work is serialized, including Activity recreation and cancellation.
    private val executor = Executors.newSingleThreadExecutor()

    // Browser coordination lives as long as the Rust engine, not a particular Activity.
    @Volatile var browserPending = false
    @Volatile var pendingAuthorization: JSONObject? = null
        private set

    fun takePendingAuthorization(): JSONObject? {
        val authorization = pendingAuthorization
        pendingAuthorization = null
        return authorization
    }

    fun submit(operation: String, args: JSONObject, host: AppHost, completion: (JSONObject) -> Unit) {
        executor.execute {
            val result = try {
                JSONObject(request(JSONObject().put("operation", operation).put("args", args).toString(), host))
            } catch (_: Exception) {
                JSONObject().put("error", "bridge_failure")
            }
            when (operation) {
                "begin_sign_in" -> {
                    pendingAuthorization = result.optJSONObject("data")
                    if (pendingAuthorization == null) browserPending = false
                }
                "cancel_sign_in", "finish_sign_in" -> {
                    pendingAuthorization = null
                    browserPending = false
                }
            }
            completion(result)
        }
    }

    val destinations: List<String> by lazy {
        (0 until tabCount()).map { index ->
            val bytes = ArrayList<Byte>()
            var offset = 0
            while (true) {
                val value = tabIdByte(index, offset++)
                if (value < 0) break
                bytes.add(value.toByte())
            }
            bytes.toByteArray().toString(Charsets.UTF_8)
        }
    }
}
