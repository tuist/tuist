package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toolbar
import org.json.JSONArray
import org.json.JSONObject

typealias AtlasAccountRequest = (JSONObject, (Result<JSONObject>) -> Unit) -> Unit

class AtlasAIAccountsScreen(
    private val activity: Activity,
    private val server: String,
    private val request: AtlasAccountRequest,
    private val openBrowser: (Uri) -> Unit,
    private val signOut: () -> Unit,
) {
    private val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val toolbar = Toolbar(activity).apply { minimumHeight = dp(56) }
    private val scroll =
        ScrollView(activity).apply {
            setOnApplyWindowInsetsListener { target, insets ->
                target.setPadding(insets.systemWindowInsetLeft, 0, insets.systemWindowInsetRight, insets.systemWindowInsetBottom)
                insets
            }
            addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setOnApplyWindowInsetsListener { target, insets ->
                target.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                insets
            }
            addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    private val handler = Handler(Looper.getMainLooper())
    private var providers = JSONArray()
    private var login: JSONObject? = null
    private var page = "settings"
    private var pendingRequests = 0
    private var generation = 0
    private var loginDeadline = 0L
    private var closed = false
    private var message: String? = null
    private var dialog: AlertDialog? = null

    init {
        activity.setActionBar(toolbar)
        activity.actionBar?.setDisplayHomeAsUpEnabled(true)
        toolbar.setNavigationOnClickListener {
            @Suppress("DEPRECATION")
            activity.onBackPressed()
        }
        content.setPadding(dp(16), dp(16), dp(16), dp(24))
        render()
    }

    fun load() {
        perform(JSONObject().put("action", "list")) { result ->
            result.onSuccess { providers = it.getJSONArray("providers") }
        }
    }

    fun back(): Boolean {
        if (page == "settings") return false
        cancelSignIn()
        page = "settings"
        render()
        return true
    }

    fun close() {
        activity.setActionBar(null)
        closed = true
        dialog?.dismiss()
        cancelSignIn()
    }

    private fun metadata(provider: String): JSONObject? =
        (0 until providers.length()).map { providers.getJSONObject(it) }.firstOrNull { it.optString("provider") == provider }

    private fun render() {
        if (closed) return
        content.removeAllViews()
        activity.title = if (page == "settings") "Settings" else "ChatGPT"
        if (page == "settings") {
            heading("Account")
            text(Uri.parse(server).host ?: server)
            heading("AI accounts")
            row("Claude", status("claude")) { claude() }
            row("ChatGPT", status("chatgpt")) {
                page = "chatgpt"
                render()
            }
            text("Sessions you start will use your connected account for inference. User-started sessions are not available yet.")
            heading("Session")
            button("Sign out") { signOut() }
        } else {
            text("Connect your ChatGPT subscription on OpenAI's website. Atlas never asks for your OpenAI password.")
            val pending = login
            if (pending != null) {
                heading(pending.getString("user_code"))
                text("Enter this code only if you started this sign-in. It expires in 15 minutes.")
                button("Continue to ChatGPT", enabled = true) { openBrowser(Uri.parse(pending.getString("verification_url"))) }
                button("Cancel sign-in", enabled = true) { cancelSignIn() }
            } else if (metadata("chatgpt")?.optBoolean("login_available") == true) {
                button("Sign in with ChatGPT") { startSignIn() }
            } else if (metadata("chatgpt") != null) {
                text("ChatGPT sign-in has not been enabled by your Atlas administrator.")
            } else {
                button("Load connection status") { load() }
            }
            text("Your existing connection stays in place until sign-in succeeds. Leaving this page cancels pending sign-in.")
            if (metadata("chatgpt")?.optBoolean("credential_configured") == true) {
                button("Disconnect ChatGPT") { disconnect("chatgpt", "ChatGPT") }
            }
        }
        if (pendingRequests > 0) text("Loading…")
        message?.let {
            text(it)
            button("Try again") { load() }
        }
    }

    private fun status(provider: String): String =
        metadata(provider)?.let { if (it.optBoolean("credential_configured")) "Credentials saved" else "Not connected" }
            ?: "Not loaded"

    private fun claude() {
        val form =
            LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(24), 0, dp(24), 0)
            }
        form.addView(
            TextView(activity).apply {
                text =
                    "Install Claude Code on your computer, run claude setup-token, and follow the sign-in instructions. Paste the generated subscription token, not an Anthropic API key."
            },
        )
        val field =
            EditText(activity).apply {
                hint = "Claude token"
                setSingleLine()
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                isSaveEnabled = false
            }
        form.addView(field)
        form.addView(
            TextView(activity).apply {
                text =
                    "Atlas encrypts the token and never displays it again. Saving checks its format, not live access. Subscription terms apply."
            },
        )
        val error = TextView(activity)
        form.addView(error)
        val builder =
            AlertDialog
                .Builder(activity)
                .setTitle("Claude")
                .setView(form)
                .setPositiveButton("Save connection", null)
                .setNegativeButton("Cancel", null)
        if (metadata("claude")?.optBoolean("credential_configured") == true) {
            builder.setNeutralButton("Disconnect") { _, _ -> disconnect("claude", "Claude") }
        }
        val current = builder.create()
        dialog = current
        current.setOnShowListener {
            current.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val token = field.text.toString()
                if (token.isBlank()) {
                    field.error = "Paste the token generated by claude setup-token."
                } else {
                    field.text.clear()
                    current.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                    perform(JSONObject().put("action", "connect_claude").put("token", token)) { result ->
                        if (!closed) {
                            result.onSuccess {
                                current.dismiss()
                                load()
                            }
                            result.onFailure {
                                if (current.isShowing) {
                                    current.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                                    error.text = it.message
                                }
                            }
                        }
                    }
                }
            }
        }
        current.setOnDismissListener {
            field.text.clear()
            if (dialog === current) dialog = null
        }
        current.show()
    }

    private fun disconnect(
        provider: String,
        name: String,
    ) {
        dialog =
            AlertDialog
                .Builder(activity)
                .setTitle("Disconnect $name?")
                .setMessage("Atlas will delete its saved credentials. Revoke access separately in your $name account settings.")
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Disconnect") { _, _ ->
                    if (provider == "chatgpt") cancelSignIn()
                    perform(JSONObject().put("action", "disconnect").put("provider", provider)) { result ->
                        result.onSuccess { if (!closed) load() }
                    }
                }.show()
    }

    private fun startSignIn() {
        val current = ++generation
        perform(JSONObject().put("action", "start_chatgpt")) { result ->
            result.onSuccess { started ->
                if (closed || generation != current) {
                    perform(JSONObject().put("action", "cancel_chatgpt").put("login_id", started.getString("login_id"))) {}
                } else {
                    loginDeadline = SystemClock.elapsedRealtime() + 900_000
                    login = started
                    schedulePoll(current)
                }
            }
        }
    }

    private fun schedulePoll(current: Int) {
        val pending = login ?: return
        handler.postDelayed({
            if (!closed && current == generation) {
                if (SystemClock.elapsedRealtime() >= loginDeadline) {
                    login = null
                    message = "ChatGPT sign-in expired. Start again."
                    render()
                    return@postDelayed
                }
                perform(JSONObject().put("action", "poll_chatgpt").put("login_id", pending.getString("login_id"))) { result ->
                    if (!closed && current == generation) {
                        result.onSuccess {
                            if (it.optString("status") == "connected") {
                                login = null
                                load()
                            } else {
                                schedulePoll(current)
                            }
                        }
                        result.onFailure {
                            if ((it as? AuthFailure)?.kind in listOf("login_expired", "sign_in_required")) {
                                login = null
                            } else {
                                schedulePoll(current)
                            }
                        }
                    }
                }
            }
        }, pending.getLong("interval") * 1000)
    }

    private fun cancelSignIn() {
        generation += 1
        handler.removeCallbacksAndMessages(null)
        val pending = login
        login = null
        if (pending != null) {
            perform(JSONObject().put("action", "cancel_chatgpt").put("login_id", pending.getString("login_id"))) {}
        }
        render()
    }

    private fun perform(
        action: JSONObject,
        complete: (Result<JSONObject>) -> Unit,
    ) {
        pendingRequests += 1
        render()
        request(action) { result ->
            pendingRequests -= 1
            if (!closed) message = result.exceptionOrNull()?.message
            complete(result)
            render()
        }
    }

    private fun heading(label: String) {
        content.addView(
            TextView(activity).apply {
                text = label
                textSize = 18f
                setPadding(0, dp(24), 0, dp(12))
            },
        )
    }

    private fun text(value: String) {
        content.addView(
            TextView(activity).apply {
                text = value
                textSize = 16f
                setPadding(0, dp(8), 0, dp(16))
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = pendingRequests == 0,
        action: () -> Unit,
    ) {
        content.addView(
            Button(activity).apply {
                text = label
                isEnabled = enabled
                setOnClickListener { action() }
            },
        )
    }

    private fun row(
        label: String,
        summary: String,
        action: () -> Unit,
    ) {
        val row = activity.layoutInflater.inflate(android.R.layout.simple_list_item_2, content, false)
        row.findViewById<TextView>(android.R.id.text1).text = label
        row.findViewById<TextView>(android.R.id.text2).text = summary
        row.isFocusable = true
        row.setBackgroundResource(android.R.drawable.list_selector_background)
        row.setOnClickListener { action() }
        content.addView(row)
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()
}
