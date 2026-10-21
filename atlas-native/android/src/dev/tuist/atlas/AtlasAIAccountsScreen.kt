package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.net.Uri
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toolbar

class AtlasAIAccountsScreen(
    private val activity: Activity,
    private val server: String,
    private val accounts: AtlasAIAccountsModel,
    private val openBrowser: (Uri) -> Unit,
    private val navigateUp: () -> Unit,
    private val signOut: () -> Unit,
) {
    private val content = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val toolbar = Toolbar(activity).apply { minimumHeight = dp(56) }
    private val scroll =
        ScrollView(activity).apply {
            addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        }
    val view =
        LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            isFocusableInTouchMode = true
            setOnApplyWindowInsetsListener { target, insets ->
                if (Build.VERSION.SDK_INT >= 30) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                    val bottom = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime()).bottom
                    target.setPadding(bars.left, bars.top, bars.right, 0)
                    scroll.setPadding(0, 0, 0, bottom)
                } else {
                    target.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                    scroll.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
                }
                insets
            }
            addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        }
    private var closed = false
    private var dialog: AlertDialog? = null
    private var tokenField: EditText? = null
    private var showingTokenHelp = false
    private var profile: AtlasProfileModel? = null
    private var navigationChanged: () -> Unit = {}
    private val renderListener: () -> Unit = { render() }

    init {
        activity.setActionBar(toolbar)
        activity.actionBar?.setDisplayHomeAsUpEnabled(true)
        toolbar.setNavigationOnClickListener { navigateUp() }
        content.setPadding(dp(16), dp(16), dp(16), dp(24))
        if (accounts.page == "claude") createTokenField()
        accounts.listener = renderListener
        render()
    }

    fun profile(
        model: AtlasProfileModel,
        changed: () -> Unit,
    ) {
        profile = model
        navigationChanged = changed
        model.listener = renderListener
        render()
    }

    fun load() {
        accounts.load()
        profile?.load()
    }

    fun back(): Boolean {
        if (accounts.page == "settings") return false
        clearToken()
        scroll.scrollTo(0, 0)
        accounts.open("settings")
        accounts.cancelLogin()
        return true
    }

    fun close(cancelPending: Boolean = true) {
        activity.setActionBar(null)
        closed = true
        clearToken()
        dialog?.dismiss()
        if (accounts.listener === renderListener) accounts.listener = null
        if (profile?.listener === renderListener) profile?.listener = null
        if (cancelPending) accounts.cancelLogin()
    }

    private fun render() {
        if (closed) return
        val focused = accounts.page == "claude" && tokenField?.hasFocus() == true
        val position = scroll.scrollY
        content.removeAllViews()
        activity.title =
            when (accounts.page) {
                "claude" -> "Claude"
                "chatgpt" -> "ChatGPT"
                else -> if (profile != null) "Profile" else "Settings"
            }
        when (accounts.page) {
            "settings" -> {
                val identity = profile
                if (identity != null) {
                    text(identity.name.ifBlank { "Atlas teammate" }).apply {
                        textSize = 26f
                        gravity = android.view.Gravity.CENTER
                        if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
                    }
                    row("Email", identity.email.ifBlank { "Not loaded" })
                } else {
                    heading("Account")
                }
                row("Atlas server", if (identity != null) server else Uri.parse(server).host ?: server)
                if (identity != null) {
                    row("Server version", identity.version.ifBlank { if (identity.busy) "Loading…" else "Unavailable" })
                    identity.error?.let { text(it) }
                    button("Refresh profile", enabled = !identity.busy, primary = false) { identity.load() }
                }
                heading("AI accounts")
                row("Claude", status("claude")) {
                    showingTokenHelp = false
                    createTokenField()
                    scroll.scrollTo(0, 0)
                    accounts.open("claude")
                }
                row("ChatGPT", status("chatgpt")) {
                    scroll.scrollTo(0, 0)
                    accounts.open("chatgpt")
                }
                text("These accounts will power sessions you start. Sessions aren’t available yet.")
                heading("Session")
                button("Sign out", enabled = true, primary = false) {
                    if (profile == null) {
                        signOut()
                    } else {
                        dialog =
                            AlertDialog
                                .Builder(activity)
                                .setTitle("Sign out of Atlas?")
                                .setMessage("Your local session and unsaved drafts will be cleared.")
                                .setPositiveButton("Sign out") { _, _ -> signOut() }
                                .setNegativeButton("Cancel", null)
                                .show()
                    }
                }
            }
            "claude" -> renderClaude()
            else -> renderChatGPT()
        }
        if (accounts.busy && accounts.login == null) progress("Loading…")
        accounts.message?.let {
            text(it).accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
            button("Try again", primary = false) { accounts.load() }
        }
        if (focused) tokenField?.requestFocus()
        scroll.post { if (!closed && !focused) scroll.scrollTo(0, position) }
        navigationChanged()
    }

    private fun renderChatGPT() {
        text("Connect your ChatGPT subscription on OpenAI's website. Atlas never asks for your OpenAI password.")
        val pending = accounts.login
        if (pending != null) {
            text(pending.getString("user_code")).apply {
                textSize = 28f
                typeface = android.graphics.Typeface.MONOSPACE
                setTextIsSelectable(true)
                isSaveEnabled = false
            }
            text("Only use this code for a sign-in you started. Valid for 15 minutes.")
            progress("Waiting for authorization…")
            button("Continue to ChatGPT", enabled = true) { openBrowser(Uri.parse(pending.getString("verification_url"))) }
            button("Cancel sign-in", enabled = true, primary = false) { accounts.cancelLogin() }
        } else if (accounts.pendingLoginId != null) {
            text("Finish cancelling your previous sign-in before starting another.")
            button("Retry cancellation") { accounts.load() }
        } else if (accounts.metadata("chatgpt")?.optBoolean("login_available") == true) {
            button("Sign in with ChatGPT") { accounts.startSignIn() }
        } else if (accounts.metadata("chatgpt") != null) {
            text("ChatGPT sign-in has not been enabled by your Atlas administrator.")
        } else {
            button("Load connection status") { accounts.load() }
        }
        text("Your existing connection stays in place until sign-in succeeds. Leaving this page cancels pending sign-in.")
        if (accounts.metadata("chatgpt")?.optBoolean("credential_configured") == true) {
            button(
                "Disconnect ChatGPT",
                enabled = !accounts.busy && accounts.login == null,
                primary = false,
            ) { disconnect("chatgpt", "ChatGPT") }
        }
    }

    private fun status(provider: String): String =
        accounts.metadata(provider)?.let { if (it.optBoolean("credential_configured")) "Credentials saved" else "Not connected" }
            ?: "Not loaded"

    private fun createTokenField() {
        tokenField =
            EditText(activity).apply {
                id = View.generateViewId()
                hint = "Paste subscription token"
                setSingleLine()
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING or EditorInfo.IME_FLAG_NO_EXTRACT_UI
                importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
                isSaveEnabled = false
                minimumHeight = dp(48)
                setOnEditorActionListener { _, action, _ ->
                    if (action == EditorInfo.IME_ACTION_DONE) {
                        saveClaude()
                        true
                    } else {
                        false
                    }
                }
            }
    }

    private fun renderClaude() {
        val field = tokenField ?: return
        text("Use your Claude Code subscription.")
        text("Subscription token").labelFor = field.id
        field.isEnabled = !accounts.busy
        content.addView(field)
        text("Encrypted and never shown again. Saving checks format, not live access.")
        button("Save connection") { saveClaude() }
        button(if (showingTokenHelp) "Hide token instructions" else "How to get a token", primary = false) {
            showingTokenHelp = !showingTokenHelp
            render()
        }
        if (showingTokenHelp) {
            text("On your computer, install Claude Code and run:")
            text("claude setup-token").apply {
                typeface = android.graphics.Typeface.MONOSPACE
                setTextIsSelectable(true)
            }
            text(
                "Follow the sign-in instructions, then paste the subscription token above. " +
                    "Use a Claude subscription token, not an Anthropic API key. Subscription terms apply.",
            )
        }
        if (accounts.metadata("claude")?.optBoolean("credential_configured") == true) {
            button("Disconnect Claude", primary = false) { disconnect("claude", "Claude") }
        }
    }

    private fun saveClaude() {
        val field = tokenField ?: return
        if (accounts.busy) return
        val token = field.text.toString()
        if (token.isBlank()) {
            field.error = "Paste the token generated by claude setup-token."
            field.requestFocus()
            return
        }
        field.error = null
        clearToken()
        accounts.saveClaude(token)
    }

    private fun clearToken() {
        tokenField?.text?.clear()
        tokenField?.clearFocus()
        view.requestFocus()
        view.windowToken?.let { token ->
            (activity.getSystemService(Activity.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(token, 0)
        }
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
                .setPositiveButton("Disconnect") { _, _ -> accounts.disconnect(provider) }
                .show()
    }

    private fun heading(label: String) {
        content.addView(
            TextView(activity).apply {
                text = label
                textSize = 14f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                if (Build.VERSION.SDK_INT >= 28) isAccessibilityHeading = true
                setPadding(0, dp(24), 0, dp(12))
            },
        )
    }

    private fun text(value: String): TextView =
        TextView(activity).apply {
            text = value
            textSize = 16f
            setPadding(0, dp(8), 0, dp(16))
            content.addView(this)
        }

    private fun progress(label: String) {
        content.addView(
            LinearLayout(activity).apply {
                gravity = android.view.Gravity.CENTER_VERTICAL
                setPadding(0, dp(8), 0, dp(8))
                addView(ProgressBar(activity), LinearLayout.LayoutParams(dp(24), dp(24)))
                addView(
                    TextView(activity).apply {
                        text = label
                        textSize = 16f
                        setPadding(dp(12), 0, 0, 0)
                    },
                )
            },
        )
    }

    private fun button(
        label: String,
        enabled: Boolean = !accounts.busy,
        primary: Boolean = true,
        action: () -> Unit,
    ) {
        content.addView(
            Button(activity, null, if (primary) android.R.attr.buttonStyle else android.R.attr.borderlessButtonStyle).apply {
                text = label
                isAllCaps = false
                minHeight = dp(48)
                isEnabled = enabled
                setOnClickListener { action() }
            },
        )
    }

    private fun row(
        label: String,
        summary: String,
        action: (() -> Unit)? = null,
    ) {
        val row = activity.layoutInflater.inflate(android.R.layout.simple_list_item_2, content, false)
        row.minimumHeight = dp(72)
        row.setPaddingRelative(0, dp(8), 0, dp(8))
        row.findViewById<TextView>(android.R.id.text1).apply {
            text = label
            textSize = 16f
            isSingleLine = false
        }
        row.findViewById<TextView>(android.R.id.text2).apply {
            text = summary
            textSize = 14f
            isSingleLine = false
        }
        if (action != null) {
            row.isFocusable = true
            row.setBackgroundResource(android.R.drawable.list_selector_background)
            row.setOnClickListener { action() }
        }
        if (Build.VERSION.SDK_INT >= 28) row.isScreenReaderFocusable = true
        content.addView(row)
    }

    private fun dp(value: Int): Int = (value * activity.resources.displayMetrics.density).toInt()
}
