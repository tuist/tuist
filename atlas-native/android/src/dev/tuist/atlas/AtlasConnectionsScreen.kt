package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

class AtlasConnectionsScreen(
    private val activity: Activity,
    private val model: AtlasConnectionsModel,
    private val ownDialog: (AlertDialog) -> Unit,
) {
    val view = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }

    init {
        model.connections.forEach { connection ->
            val provider = connection.getString("provider")
            val name = connection.getString("name")
            val status = connection.getString("status")
            val connected = status != "not_connected"
            val configured = connection.getBoolean("configured")
            text(name, 20f)
            text(
                when {
                    status == "needs_authorization" -> "Reconnect required"
                    status == "connected" -> connection.optString("account_name", "Connected")
                    !configured -> "Not enabled on this server"
                    else -> "Not connected"
                },
            )
            button(if (connected) "Reconnect $name" else "Connect $name", configured && !model.busy && !model.waiting) {
                model.connect(provider)
            }
            if (connected) {
                button("Disconnect $name", !model.busy && !model.waiting) {
                    AlertDialog
                        .Builder(activity)
                        .setTitle("Disconnect $name?")
                        .setMessage("Atlas will no longer have access through this connection.")
                        .setNegativeButton("Cancel", null)
                        .setPositiveButton("Disconnect") { _, _ -> model.disconnect(provider) }
                        .create()
                        .also {
                            ownDialog(it)
                            it.show()
                        }
                }
            }
        }
        text("Connect your personal GitHub, Slack and Google accounts. Authorization opens in your browser and returns to Atlas.")
        if (model.busy) view.addView(ProgressBar(activity))
        if (model.waiting) {
            text("Finish connecting in your browser, or cancel to try again.")
            button("Cancel connection", !model.busy) { model.cancel() }
        }
        model.message?.let { text(it) }
        button("Refresh connections", !model.busy && !model.waiting) { model.load() }
    }

    private fun text(
        value: String,
        size: Float = 16f,
    ) {
        view.addView(
            TextView(activity).apply {
                text = value
                textSize = size
                setPadding(0, dp(8), 0, dp(8))
            },
        )
    }

    private fun button(
        title: String,
        enabled: Boolean,
        action: () -> Unit,
    ) {
        view.addView(
            Button(activity).apply {
                text = title
                isAllCaps = false
                minHeight = dp(48)
                isEnabled = enabled
                setOnClickListener { action() }
            },
            LinearLayout.LayoutParams(-1, -2),
        )
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()
}
