package dev.tuist.code

import org.json.JSONObject
import java.util.concurrent.Executors

object AppCore {
    init {
        System.loadLibrary("tuist_app_core")
    }

    private external fun tabCount(): Int
    private external fun tabIdByte(index: Int, offset: Int): Int
    private external fun request(input: String, host: AppHost): String

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
