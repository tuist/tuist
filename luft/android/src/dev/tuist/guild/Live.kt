package dev.tuist.guild

import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch

/**
 * Follows the inbox's live socket on its own thread until [stop], so the threads list
 * changes as soon as a thread starts working, answers or finishes. The core decides
 * everything about it (`live_wait`, `live_connect`, `live_tick`, `live_receive`): when to
 * connect, heartbeat and reconnect, and how often the list may reload (`refresh_ms`).
 * [refresh] is called on this thread; refreshes asked for meanwhile fold into one.
 */
class InboxLive(private val host: AppHost, private val refresh: () -> Unit) {
    @Volatile private var running = true
    private val socket = UUID.randomUUID().toString()
    private val thread = Thread({ run() }, "LuftInboxLive").apply { isDaemon = true; start() }

    fun stop() {
        running = false
        thread.interrupt()
    }

    private fun run() {
        var refreshed = 0L
        var pending = false
        try {
            while (running) {
                Thread.sleep(call("live_wait")?.optLong("delay_ms") ?: 0)
                val plan = call("live_connect", JSONObject().put("id", INBOX)) ?: continue
                val connection = try {
                    WebSocket.connect(plan.getString("url"), plan.getJSONArray("protocols").strings())
                } catch (_: Exception) { continue }
                try {
                    connection.send(plan.getString("join"))
                    val tick = plan.optLong("tick_ms", 30_000)
                    val spacing = plan.optLong("refresh_ms", 0)
                    var ticked = System.currentTimeMillis()
                    connected@ while (running) {
                        Thread.sleep(READ_MS)
                        val (frames, closed) = connection.read()
                        for (frame in frames) {
                            val out = call("live_receive", JSONObject().put("id", INBOX).put("message", frame)) ?: continue
                            out.optJSONArray("replies").strings().forEach(connection::send)
                            if (out.optBoolean("refresh")) pending = true
                            if (out.optBoolean("reconnect")) break@connected
                        }
                        if (closed) break
                        val now = System.currentTimeMillis()
                        if (now - ticked >= tick) {
                            ticked = now
                            val out = call("live_tick") ?: break
                            out.optJSONArray("send").strings().forEach(connection::send)
                            if (out.optBoolean("reconnect")) break
                        }
                        if (pending && now - refreshed >= spacing) {
                            pending = false
                            refreshed = now
                            refresh()
                        }
                    }
                } catch (_: IOException) {
                } finally {
                    connection.close()
                }
            }
        } catch (_: InterruptedException) {
        } finally {
            AppCore.submit("live_close", JSONObject().put("socket", socket), host) { }
        }
    }

    /** Runs a live operation for this socket on the core's queue and waits for its data; null on an error. */
    private fun call(operation: String, args: JSONObject = JSONObject()): JSONObject? {
        val done = CountDownLatch(1)
        var result: JSONObject? = null
        AppCore.submit(operation, args.put("socket", socket), host) { result = it; done.countDown() }
        done.await()
        return result?.optJSONObject("data")
    }

    private companion object {
        /** The core's ID for the whole inbox rather than one thread. */
        const val INBOX = "inbox"
        /** How often frames are read; the socket buffers them meanwhile. */
        const val READ_MS = 250L
    }
}

private fun JSONArray?.strings(): List<String> = if (this == null) emptyList()
    else (0 until length()).mapNotNull { optString(it, null) }
