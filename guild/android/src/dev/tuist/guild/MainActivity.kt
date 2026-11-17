package dev.tuist.guild

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : Activity() {
    private lateinit var host: AppHost
    private lateinit var content: LinearLayout
    private val handler = Handler(Looper.getMainLooper())
    private var view = JSONObject()
    // The legacy preview browser is local; shared destinations belong to the core.
    private var previewsSelected = false
    private val screen: String
        get() = if (previewsSelected) "previews" else view.optJSONObject("navigation")?.optString("tab", "threads") ?: "threads"
    private val threadId: String?
        get() = view.optJSONObject("navigation")?.string("thread_id")?.takeIf { it.isNotBlank() }
    private var intentConsumed = false
    // Adding another profile shows the login screen over the signed-in workspace.
    private var addingProfile = false
    private var ticket = 0L
    private var busy = false
    private var browserPending: Boolean
        get() = AppCore.browserPending
        set(value) { AppCore.browserPending = value }
    private var project: String? = null
    private var track: String? = null
    private var search = ""
    private var page = 0
    private var hasNext = false
    private var previews = mutableListOf<JSONObject>()
    private var projects = emptyList<JSONObject>()
    private var tracks: JSONObject? = null
    private var detail: JSONObject? = null
    private var debounce: Runnable? = null
    private var threads = emptyList<JSONObject>()
    private var conversation: JSONObject? = null
    private var reply = ""
    private var follow: Runnable? = null
    private var update: JSONObject? = null
    private val searchInputId = View.generateViewId()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = AppHost(applicationContext)
        previewsSelected = savedInstanceState?.getBoolean("previews_selected") ?: false
        intentConsumed = savedInstanceState?.getBoolean("intent_consumed") ?: false
        addingProfile = savedInstanceState?.getBoolean("adding_profile") ?: false
        // Loads profiles and migrates local stores before any screen reads them.
        call("boot") {
            render()
            if (intentConsumed || !consumeIntent(intent)) {
                if (AppCore.pendingAuthorization != null) launchPendingSignIn()
                else load()
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("previews_selected", previewsSelected)
        outState.putBoolean("intent_consumed", intentConsumed)
        outState.putBoolean("adding_profile", addingProfile)
        super.onSaveInstanceState(outState)
    }

    // Coming back from the browser or another app is when a new build may have landed.
    override fun onResume() {
        super.onResume()
        checkForUpdate()
        // Send what was written offline, such as threads started on a plane.
        if (active() != null) AppCore.submit("flush_outbox", JSONObject(), host) { }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intentConsumed = false
        consumeIntent(intent)
    }

    override fun onDestroy() {
        ticket++
        handler.removeCallbacksAndMessages(null)
        if (browserPending && isFinishing && !isChangingConfigurations) {
            AppCore.submit("cancel_sign_in", JSONObject(), host) { }
        }
        super.onDestroy()
    }

    private fun consumeIntent(intent: Intent): Boolean {
        val uri = intent.data
        val navigation = intent.getStringExtra("navigate")
        // Remove both sources before submitting anything. Saved state also protects
        // recreation after process death, when Android may restore the launch Intent.
        intent.data = null
        intent.removeExtra("navigate")
        intentConsumed = true
        if (uri?.scheme == "tuist-guild" && uri.host == "oauth-callback" && uri.path.isNullOrEmpty()) {
            browserPending = false
            call("finish_sign_in", JSONObject().put("url", uri.toString())) {
                reset(); addingProfile = false; previewsSelected = false; render(); load()
            }
            return true
        }
        val url = navigation ?: uri?.toString() ?: return false
        navigate("navigate", JSONObject().put("url", url))
        return true
    }

    private fun navigate(operation: String, args: JSONObject = JSONObject()) {
        call(operation, args) {
            previewsSelected = false
            render(); load()
        }
    }

    private fun call(operation: String, args: JSONObject = JSONObject(), onFailure: (() -> Unit)? = null,
                     done: (Any?) -> Unit = { render() }) {
        // A URL is only a proposed destination. Keep the current data request
        // (including chained tracks/previews loads) alive until it is accepted.
        val navigationRequest = operation == "navigate" || operation == "select_tab" || operation == "navigation_back"
        val requestTicket = if (navigationRequest) ticket else ++ticket
        val generation = view.optLong("generation", -1)
        if (!navigationRequest) busy = true
        AppCore.submit(operation, args, host) { result ->
            runOnUiThread {
                if (isDestroyed || (!navigationRequest && requestTicket != ticket)) return@runOnUiThread
                if (!navigationRequest) busy = false
                val next = result.optJSONObject("view")
                if (next != null && next.optLong("generation", -1) < generation) return@runOnUiThread
                if (next != null) {
                    val oldNavigation = view.optJSONObject("navigation")
                    val nextNavigation = next.optJSONObject("navigation")
                    if (next.optLong("generation", -1) == view.optLong("generation", -1) &&
                        nextNavigation != null && oldNavigation != null &&
                        nextNavigation.optLong("revision") < oldNavigation.optLong("revision")) return@runOnUiThread
                    if (view.has("generation") && (next.optLong("generation", -1) != view.optLong("generation", -1) ||
                        next.optString("active_profile_id") != view.optString("active_profile_id"))) reset()
                    if (nextNavigation?.optLong("revision") != oldNavigation?.optLong("revision")) {
                        follow?.let(handler::removeCallbacks)
                        conversation = null; reply = ""
                    }
                    view = next
                }
                if (!result.isNull("error") && result.optString("error").isNotBlank()) {
                    if (operation == "begin_sign_in") browserPending = false
                    if (onFailure != null) { onFailure(); return@runOnUiThread }
                    // Backend and OAuth error text can contain credentials; expose only localized copy.
                    toast(R.string.request_failed)
                    render()
                    return@runOnUiThread
                }
                if (navigationRequest) {
                    ticket++
                    busy = false
                    debounce?.let(handler::removeCallbacks)
                }
                done(result.opt("data"))
            }
        }
    }

    private fun active(): JSONObject? = view.optJSONArray("profiles").objects()
        .firstOrNull { it.optString("id") == view.optString("active_profile_id") }

    private fun reset() {
        debounce?.let(handler::removeCallbacks)
        follow?.let(handler::removeCallbacks)
        previewsSelected = false
        project = null; track = null; search = ""; page = 0
        projects = emptyList(); previews.clear(); tracks = null; detail = null
        threads = emptyList(); threadsSignInRequired = false; conversation = null; reply = ""
    }

    /** Loads the current screen's data. */
    private fun load() {
        if (active() == null) return
        checkForUpdate()
        when (screen) {
            "previews" -> loadProjects()
            "threads" -> threadId?.let { fetchThread(it) } ?: loadThreads()
        }
    }

    @Deprecated("Activity predates OnBackPressedDispatcher")
    override fun onBackPressed() {
        if (addingProfile && active() != null) cancelAddingProfile()
        else if (screen == "threads" && threadId != null) closeConversation()
        else @Suppress("DEPRECATION") super.onBackPressed()
    }

    private fun render() {
        val login = active() == null || addingProfile
        // Dark status bar icons, except over the login screen's dark artwork.
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (if (login) night else dark) 0 else View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        if (login) { setContentView(loginScreen(night)); return }
        val focusedSearch = (currentFocus as? EditText)?.takeIf { it.id == searchInputId }
        val selection = focusedSearch?.selectionStart ?: -1
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val pad = (16 * resources.displayMetrics.density).toInt()
            setPadding(pad, pad, pad, pad)
            setOnApplyWindowInsetsListener { v, insets ->
                v.setPadding(pad + insets.systemWindowInsetLeft, pad + insets.systemWindowInsetTop,
                    pad + insets.systemWindowInsetRight, pad + insets.systemWindowInsetBottom)
                insets
            }
        }
        root.setBackgroundColor(noora("surface-background-primary"))
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        text(getString(when (screen) {
            "profile" -> R.string.profile
            "threads" -> R.string.threads
            else -> R.string.previews
        }), 28f)
        if (busy) text(getString(R.string.loading))
        when (screen) {
            "profile" -> profileScreen()
            "threads" -> threadsScreen()
            else -> previewScreen()
        }
        // A conversation takes the whole screen, as on iOS; Back returns to the inbox.
        if (screen == "threads" && threadId != null) { setContentView(root); return }
        root.addView(styled(Button(this)).apply {
            setText(R.string.threads)
            setOnClickListener {
                if (!busy && !browserPending) navigate("select_tab", JSONObject().put("tab", "threads"))
            }
        })
        root.addView(styled(Button(this)).apply {
            setText(R.string.previews)
            setOnClickListener {
                if (!busy && !browserPending) {
                    follow?.let(handler::removeCallbacks)
                    previewsSelected = true; render(); if (projects.isEmpty()) loadProjects()
                }
            }
        })
        root.addView(styled(Button(this)).apply {
            setText(R.string.profile)
            setOnClickListener {
                if (!busy) {
                    if (screen == "profile" && !browserPending) chooseProfile()
                    else navigate("select_tab", JSONObject().put("tab", "profile"))
                }
            }
            setOnLongClickListener { if (!busy && !browserPending) chooseProfile(); true }
        })
        setContentView(root)
        if (selection >= 0) findViewById<EditText>(searchInputId)?.let {
            it.requestFocus()
            it.setSelection(selection.coerceIn(0, it.text.length))
        }
    }

    private val night: Boolean
        get() = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    private val settings get() = getSharedPreferences("guild_settings", MODE_PRIVATE)

    /** The theme chosen in Profile; it stays on this device. */
    private var themeId: String
        get() = settings.getString("theme", null) ?: AppCore.defaultTheme
        set(value) { settings.edit().putString("theme", value).apply() }

    /** The theme's own appearance, or the system's. */
    private val dark: Boolean get() = AppCore.themeAppearance(themeId) ?: night

    /** A Noora token in the chosen theme for the current appearance. */
    private fun noora(name: String) = AppCore.color(themeId, name, dark)

    private fun text(value: String, size: Float = 16f) {
        content.addView(TextView(this).apply {
            text = value; textSize = size; setPadding(0, 8, 0, 8)
            setTextColor(noora("surface-label-primary"))
        })
    }

    private fun button(label: Int, primary: Boolean = false, action: () -> Unit) = button(getString(label), primary, action)
    private fun button(label: String, primary: Boolean = false, action: () -> Unit) {
        content.addView(styled(Button(this).apply {
            text = label
            setOnClickListener { if (!busy) action() }
        }, primary), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })
    }

    /** Noora's primary or secondary button. */
    private fun styled(button: Button, primary: Boolean = false): Button = button.apply {
        isAllCaps = false
        stateListAnimator = null
        setTextColor(noora(if (primary) "button-primary-label" else "button-secondary-label"))
        background = GradientDrawable().apply {
            cornerRadius = dp(8).toFloat()
            setColor(noora(if (primary) "button-primary-background" else "button-secondary-background"))
            if (!primary) setStroke(dp(1), noora("surface-border-primary"))
        }
    }

    private fun profileScreen() {
        active()?.let { profile ->
            text("@${profile.optString("handle")}", 22f)
            text(profile.optString("email"))
            text(profile.optString("server"))
            if (profile.optBoolean("rejected")) text(getString(R.string.sign_in_required))
        } ?: text(getString(R.string.sign_in_required))
        if (!browserPending) button(R.string.switch_account) { chooseProfile() }
        button(getString(R.string.theme_value, AppCore.themes.firstOrNull { it.first == themeId }?.second.orEmpty())) {
            chooseTheme()
        }
        if (browserPending) button(R.string.cancel_sign_in) {
            browserPending = false
            call("cancel_sign_in")
        } else button(R.string.add_profile) { signIn() }
        button(R.string.terms) { open("https://tuist.dev/terms") }
        button(R.string.privacy) { open("https://tuist.dev/privacy") }
        button(R.string.help) { open("mailto:contact@tuist.dev") }
        @Suppress("DEPRECATION")
        val version = packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        text(getString(R.string.version, version))
        update?.let { updateRow(it) }
        if (active() != null && !browserPending) {
            button(R.string.sign_out) { call("sign_out") { reset(); render() } }
            button(R.string.delete_account) {
                confirm(R.string.delete_account, R.string.delete_account_message) {
                    call("delete_account") { reset(); render() }
                }
            }
        }
    }

    /** Refreshes memberships, then offers every saved profile's accounts and organizations. */
    private fun chooseProfile() {
        // A failed refresh still lists the memberships saved earlier.
        call("organizations", onFailure = { showAccounts() }) { showAccounts() }
    }

    private fun showAccounts() {
        render()
        val accounts = view.optJSONArray("accounts").objects().filterNot { it.optBoolean("rejected") }
        val rows = accounts.map {
            val owner = if (it.optBoolean("personal")) "" else "@${it.optString("handle")} · "
            "${if (it.optBoolean("selected")) "✓ " else ""}${it.optString("name")} · $owner${it.optString("server")}"
        } + getString(R.string.add_profile) + getString(R.string.sign_out)
        AlertDialog.Builder(this).setTitle(R.string.switch_account)
            .setItems(rows.toTypedArray()) { _, i ->
                when (i) {
                    accounts.size -> signIn()
                    accounts.size + 1 -> call("sign_out") { reset(); render() }
                    else -> call("select_organization", JSONObject().put("id", accounts[i].getString("profile_id"))
                        .put("name", accounts[i].getString("name"))) { reset(); render(); load() }
                }
            }.setNegativeButton(R.string.cancel, null).show()
    }

    /** Noora follows the system appearance; Omarchy's themes have their own. */
    private fun chooseTheme() {
        val themes = AppCore.themes
        AlertDialog.Builder(this).setTitle(R.string.theme)
            .setSingleChoiceItems(themes.map { it.second }.toTypedArray(), themes.indexOfFirst { it.first == themeId }) { dialog, i ->
                themeId = themes[i].first
                dialog.dismiss()
                render()
            }.setNegativeButton(R.string.cancel, null).show()
    }

    private fun signIn() {
        addingProfile = true
        render()
    }

    private fun cancelAddingProfile() {
        if (browserPending) {
            browserPending = false
            call("cancel_sign_in")
        }
        addingProfile = false
        render()
    }

    private fun selfHostedSignIn() {
        val input = EditText(this).apply {
            hint = "https://example.com"
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            setSingleLine(true)
            // Like the shipping app, prefill the last self-hosted server the user signed in to.
            view.optJSONArray("profiles").objects().map { it.optString("server") }
                .lastOrNull { !it.startsWith("https://tuist.dev") }?.let(::setText)
        }
        AlertDialog.Builder(this).setTitle(R.string.self_hosted).setMessage(R.string.self_hosted_message).setView(input)
            .setPositiveButton(R.string.sign_in) { _, _ ->
                val server = input.text.toString().trim()
                val uri = Uri.parse(server)
                if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) {
                    toast(R.string.https_required); return@setPositiveButton
                }
                launchSignIn(server, "tuist")
            }.setNegativeButton(R.string.cancel, null).show()
    }

    /** The shipping app's `LoginScreen`, rebuilt with platform views. Social providers use Tuist-hosted. */
    private fun loginScreen(dark: Boolean): View {
        val labelPrimary = if (dark) 0xFFFDFDFD.toInt() else 0xFF171A1C.toInt()
        val labelTertiary = if (dark) 0xFF696C72.toInt() else 0xFF9DA6AF.toInt()
        val root = FrameLayout(this)
        root.addView(ImageView(this).apply {
            setImageResource(R.drawable.launch_background)
            scaleType = ImageView.ScaleType.CENTER_CROP
        }, FrameLayout.LayoutParams(-1, -1))
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        // Scrolls when landscape or large font sizes leave too little height.
        val scroll = ScrollView(this).apply { isFillViewport = true }
        scroll.addView(column, FrameLayout.LayoutParams(-1, -1))
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        if (active() != null) column.addView(TextView(this).apply {
            setText(R.string.cancel)
            setTextColor(labelPrimary)
            textSize = 16f
            setPadding(dp(16), dp(12), dp(16), dp(12))
            setOnClickListener { cancelAddingProfile() }
        }, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.START })
        column.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        column.addView(ImageView(this).apply {
            setImageResource(R.drawable.tuist_rounded_icon)
            contentDescription = getString(R.string.app_name)
        }, LinearLayout.LayoutParams(dp(80), dp(80)).apply { topMargin = dp(32); bottomMargin = dp(32) })
        column.addView(TextView(this).apply {
            setText(R.string.login_title)
            textSize = 28f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setTextColor(labelPrimary)
        }, LinearLayout.LayoutParams(-2, -2).apply { bottomMargin = dp(12) })
        column.addView(TextView(this).apply {
            setText(if (browserPending) R.string.continue_in_browser else R.string.login_subtitle)
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(labelPrimary)
        }, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(24); rightMargin = dp(24); bottomMargin = dp(32) })
        column.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val radius = dp(32).toFloat()
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(radius, radius, radius, radius, 0f, 0f, 0f, 0f)
                setColor(if (dark) 0xCC16181C.toInt() else 0x99FFFFFF.toInt())
                setStroke(dp(2), if (dark) 0xFF1F2126.toInt() else Color.WHITE)
            }
        }
        column.addView(card, LinearLayout.LayoutParams(-1, -2))
        if (browserPending) {
            // Stays on the login screen so another provider can be chosen; the top Cancel leaves it.
            card.addView(socialButton(getString(R.string.cancel_sign_in), null, false, dark) {
                browserPending = false
                call("cancel_sign_in")
            })
        } else {
            card.addView(socialButton(getString(R.string.sign_in_tuist), R.drawable.tuist_logo, true, dark) {
                launchSignIn("https://tuist.dev", "tuist")
            })
            card.addView(socialButton(getString(R.string.sign_in_apple), R.drawable.apple_logo, false, dark) {
                launchSignIn("https://tuist.dev", "apple")
            })
            card.addView(socialButton(getString(R.string.sign_in_google), R.drawable.google_logo, false, dark) {
                launchSignIn("https://tuist.dev", "google")
            })
            card.addView(socialButton(getString(R.string.sign_in_github), R.drawable.github_logo, false, dark) {
                launchSignIn("https://tuist.dev", "github")
            })
            card.addView(LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                val line = { View(this@MainActivity).apply { setBackgroundColor(labelTertiary and 0x4DFFFFFF) } }
                addView(line(), LinearLayout.LayoutParams(0, dp(1), 1f))
                addView(TextView(this@MainActivity).apply {
                    setText(R.string.or)
                    textSize = 13f
                    setTextColor(labelTertiary)
                    setPadding(dp(8), 0, dp(8), 0)
                })
                addView(line(), LinearLayout.LayoutParams(0, dp(1), 1f))
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) })
            card.addView(socialButton(getString(R.string.self_hosted_server), R.drawable.server_icon, false, dark) {
                selfHostedSignIn()
            })
        }
        root.setOnApplyWindowInsetsListener { _, insets ->
            column.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
            card.setPadding(dp(24), dp(20), dp(24), dp(32) + insets.systemWindowInsetBottom)
            insets
        }
        return root
    }

    private fun socialButton(label: String, icon: Int?, primary: Boolean, dark: Boolean, action: () -> Unit): View {
        val text = if (primary || dark) 0xFFFDFDFD.toInt() else 0xFF171A1C.toInt()
        return LinearLayout(this).apply {
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            contentDescription = label
            setPadding(0, dp(12), 0, dp(12))
            elevation = dp(1).toFloat()
            background = GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, when {
                primary -> intArrayOf(0xFF854DFF.toInt(), if (dark) 0xFF5F00E5.toInt() else 0xFF6F2CFF.toInt())
                dark -> intArrayOf(0xFF1F2126.toInt(), 0xFF1F2126.toInt())
                else -> intArrayOf(0xFFFDFDFD.toInt(), 0xFFF7F7F8.toInt())
            }).apply {
                cornerRadius = dp(8).toFloat()
                setStroke(dp(1), if (primary) 0xE55F00E5.toInt() else 0x14000000)
            }
            icon?.let {
                addView(ImageView(this@MainActivity).apply {
                    setImageResource(it)
                    if (it == R.drawable.server_icon) setColorFilter(text)
                }, LinearLayout.LayoutParams(dp(20), dp(20)).apply { rightMargin = dp(2) })
            }
            addView(TextView(this@MainActivity).apply {
                this.text = label
                textSize = 16f
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                setTextColor(text)
                setPadding(dp(4), 0, dp(4), 0)
            })
            setOnClickListener { if (!busy) action() }
            layoutParams = LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(12) }
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun launchSignIn(server: String, provider: String) {
        val browser = CustomTabsClient.getPackageName(this, null)
        if (browser == null || !CustomTabsClient.isEphemeralBrowsingSupported(this, browser)) {
            toast(R.string.ephemeral_required); return
        }
        browserPending = true
        call("begin_sign_in", JSONObject().put("server", server).put("provider", provider)) { launchPendingSignIn() }
    }

    private fun launchPendingSignIn() {
        val payload = AppCore.takePendingAuthorization() ?: return
        val uri = payload.optString("url").let(Uri::parse)
        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null || payload.optString("callback_scheme") != "tuist-guild") {
            browserPending = false
            call("cancel_sign_in"); toast(R.string.request_failed)
            return
        }
        val browser = CustomTabsClient.getPackageName(this, null)
        if (browser == null || !CustomTabsClient.isEphemeralBrowsingSupported(this, browser)) {
            browserPending = false
            call("cancel_sign_in"); toast(R.string.ephemeral_required)
            return
        }
        try {
            CustomTabsIntent.Builder().setEphemeralBrowsingEnabled(true).build().apply {
                intent.setPackage(browser)
            }.launchUrl(this, uri)
            render()
        } catch (_: Exception) {
            browserPending = false
            call("cancel_sign_in"); toast(R.string.browser_unavailable)
        }
    }

    private fun loadProjects() {
        if (active() == null) return
        call("projects") { data ->
            projects = (data as? JSONObject)?.optJSONArray("projects").objects()
            render()
        }
    }

    /** Sessions from before Guild's first-party client must sign in again; they see why instead of an empty list. */
    private var threadsSignInRequired = false

    private fun loadThreads() {
        if (active() == null) return
        call("threads") { data ->
            threads = (data as? JSONObject)?.optJSONArray("threads").objects()
                .filter { it.optString("section") != "archived" }
            threadsSignInRequired = (data as? JSONObject)?.optString("reason") == "sign_in_required"
            render()
        }
    }

    /** The inbox, or one conversation. Conversations run on the server; there is nothing to pick. */
    private fun threadsScreen() {
        if (active() == null) return
        if (threadId != null && conversation == null) {
            button(R.string.back) { closeConversation() }
            if (!busy) button(R.string.refresh) { load() }
            return
        }
        conversation?.let { conversationScreen(it); return }
        button(R.string.start_conversation, primary = true) { startConversation() }
        button(R.string.refresh) { loadThreads() }
        if (threadsSignInRequired) {
            text(getString(R.string.threads_sign_in_required))
            active()?.let { profile ->
                if (!browserPending) button(R.string.sign_in_again, primary = true) { launchSignIn(profile.getString("server"), "tuist") }
            }
        } else if (threads.isEmpty() && !busy) text(getString(R.string.no_threads))
        threads.forEach { item ->
            button(listOf(item.string("title").ifBlank { item.string("goal") }, threadState(item.string("state")))
                .filter { it.isNotBlank() }.joinToString(" · ")) { openThread(item.getString("id")) }
        }
    }

    /**
     * Asks the core whether tuist.dev has a newer internal preview than this APK. It
     * runs beside screen requests rather than through [call], so it never cancels them,
     * and a failed check only delays the banner.
     */
    private fun checkForUpdate() {
        if (active() == null) return
        val apk = applicationInfo.sourceDir
        Thread {
            // The APK's SHA-256 is the binary ID its preview records.
            val binaryId = try {
                val digest = java.security.MessageDigest.getInstance("SHA-256")
                java.io.File(apk).inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
                }
                digest.digest().joinToString("") { "%02x".format(it) }
            } catch (_: Exception) { return@Thread }
            AppCore.submit("preview_update", JSONObject().put("platform", "android").put("binary_id", binaryId), host) { result ->
                val next = result.optJSONObject("data")?.optJSONObject("update")
                runOnUiThread {
                    if (isDestroyed || result.has("error")) return@runOnUiThread
                    update = next
                    if (!busy && screen == "profile") render()
                }
            }
        }.start()
    }

    /** Profile's row under App version: Android downloads the APK and asks to install it. */
    private fun updateRow(item: JSONObject) {
        val url = item.string("install_url")
        content.addView(LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(12), dp(12), dp(12))
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(noora("surface-background-secondary"))
                setStroke(dp(1), noora("surface-border-primary"))
            }
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                addView(TextView(context).apply {
                    setText(R.string.update_available); textSize = 16f
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(noora("surface-label-primary"))
                })
                item.string("commit").takeIf { it.isNotBlank() }?.let { commit ->
                    addView(TextView(context).apply {
                        text = getString(R.string.update_build, commit); textSize = 13f
                        typeface = Typeface.MONOSPACE
                        setTextColor(noora("surface-label-secondary"))
                    })
                }
            }, LinearLayout.LayoutParams(0, -2, 1f))
            addView(styled(Button(context), primary = true).apply {
                setText(R.string.update)
                setOnClickListener { open(url) }
            })
        }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8); bottomMargin = dp(8) })
    }

    private fun threadState(state: String): String = when (state) {
        "queued" -> getString(R.string.thread_queued)
        "running" -> getString(R.string.thread_running)
        "completed" -> getString(R.string.thread_completed)
        "failed" -> getString(R.string.thread_failed)
        "outcome_unknown" -> getString(R.string.thread_outcome_unknown)
        else -> ""
    }

    private fun startConversation() {
        val generation = view.optLong("generation", -1)
        val profile = view.optString("active_profile_id")
        val revision = view.optJSONObject("navigation")?.optLong("revision")
        val input = EditText(this).apply {
            hint = getString(R.string.conversation_prompt)
            minLines = 3
            gravity = Gravity.TOP or Gravity.START
        }
        AlertDialog.Builder(this).setTitle(R.string.new_conversation)
            .setView(input)
            .setPositiveButton(R.string.start) { _, _ ->
                if (busy || generation != view.optLong("generation", -1) ||
                    revision != view.optJSONObject("navigation")?.optLong("revision") ||
                    profile != view.optString("active_profile_id") || screen != "threads" || threadId != null) return@setPositiveButton
                val text = input.text.toString()
                if (text.isBlank()) return@setPositiveButton
                call("start_thread", JSONObject().put("content", text), onFailure = {
                    toast(R.string.start_failed); render()
                }) { data ->
                    val id = (data as? JSONObject)?.string("id")
                    if (!id.isNullOrBlank()) openThread(id) else { render(); load() }
                }
            }.setNegativeButton(R.string.cancel, null).show()
    }

    private fun openThread(id: String) {
        navigate("navigate", JSONObject().put("url", "/threads/$id"))
    }

    private fun fetchThread(id: String) {
        val generation = view.optLong("generation", -1)
        val profile = view.optString("active_profile_id")
        val revision = view.optJSONObject("navigation")?.optLong("revision")
        call("thread", JSONObject().put("id", id)) { data ->
            if (screen == "threads" && threadId == id && generation == view.optLong("generation", -1) &&
                profile == view.optString("active_profile_id") && revision == view.optJSONObject("navigation")?.optLong("revision")) {
                show(data as? JSONObject)
            }
        }
    }

    /** Shows a conversation and keeps it current while the server is answering. */
    private fun show(thread: JSONObject?) {
        follow?.let(handler::removeCallbacks)
        if (screen != "threads" || thread == null || thread.optString("id") != threadId) return
        conversation = thread
        render()
        if (!thread.optBoolean("working")) return
        val id = thread.optString("id")
        val generation = view.optLong("generation", -1)
        val revision = view.optJSONObject("navigation")?.optLong("revision")
        follow = Runnable {
            if (isDestroyed || screen != "threads" || threadId != id ||
                generation != view.optLong("generation", -1) ||
                revision != view.optJSONObject("navigation")?.optLong("revision")) return@Runnable
            if (busy) handler.postDelayed(follow!!, 2000) else fetchThread(id)
        }
        handler.postDelayed(follow!!, 2000)
    }

    private fun closeConversation() {
        navigate("navigation_back")
    }

    private fun conversationScreen(thread: JSONObject) {
        button(R.string.back) { closeConversation() }
        text(thread.string("title").ifBlank { thread.string("goal") }, 22f)
        thread.optJSONArray("messages").objects().forEach { message ->
            val body = message.string("content")
            when (message.optString("role")) {
                "user" -> content.addView(TextView(this).apply {
                    text = body
                    textSize = 16f
                    setTextIsSelectable(true)
                    gravity = Gravity.END
                    setPadding(dp(12), dp(8), dp(12), dp(8))
                    setTextColor(noora("surface-label-primary"))
                    background = GradientDrawable().apply {
                        cornerRadius = dp(12).toFloat()
                        setColor(noora("button-neutral-background-hover"))
                        setStroke(dp(1), noora("surface-border-primary"))
                    }
                    layoutParams = LinearLayout.LayoutParams(-2, -2).apply {
                        gravity = Gravity.END; leftMargin = dp(48); topMargin = dp(8); bottomMargin = dp(8)
                    }
                })
                "assistant" -> content.addView(TextView(this).apply {
                    text = body; textSize = 16f; setTextIsSelectable(true); setPadding(0, dp(8), dp(24), dp(8))
                    setTextColor(noora("surface-label-primary"))
                })
                else -> content.addView(TextView(this).apply {
                    text = body; textSize = 12f; setPadding(0, dp(4), 0, dp(4))
                    setTextColor(noora("surface-label-secondary"))
                })
            }
        }
        if (thread.optBoolean("working")) { text(getString(R.string.thinking)); return }
        content.addView(EditText(this).apply {
            setTextColor(noora("surface-label-primary"))
            setHintTextColor(noora("surface-label-tertiary"))
            hint = getString(R.string.reply)
            setText(reply)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { reply = s.toString() }
                override fun afterTextChanged(s: Editable?) {}
            })
        })
        button(R.string.send, primary = true) {
            if (reply.isBlank()) return@button
            call("send_message", JSONObject().put("id", thread.optString("id")).put("content", reply)) { data ->
                reply = ""; show(data as? JSONObject)
            }
        }
    }

    private fun projectName(item: JSONObject): String = item.optString("full_name").ifBlank {
        item.optString("full_handle").ifBlank { item.optString("name") }
    }

    private fun previewScreen() {
        if (active() == null) return
        if (project == null) {
            button(R.string.refresh) { loadProjects() }
            if (projects.isEmpty()) text(getString(R.string.no_projects))
            projects.forEach { item ->
                button(projectName(item)) {
                    project = projectName(item); track = null; search = ""; detail = null
                    previews.clear(); page = 0; hasNext = false; tracks = null
                    loadTracks()
                }
            }
            return
        }
        button(R.string.projects) {
            project = null; detail = null; render()
        }
        text(project!!, 22f)
        detail?.let { showDetail(it); return }
        tracks?.let { available ->
            val row = LinearLayout(this)
            row.addView(Button(this).apply {
                text = getString(R.string.all_tracks, available.optInt("total_count"))
                isSelected = track == null
                setOnClickListener { if (!busy) { track = null; loadPreviews(true) } }
            })
            available.optJSONArray("tracks").objects().forEach { item ->
                row.addView(Button(this).apply {
                    val name = item.optString("name")
                    text = getString(R.string.track_count, name, item.optInt("count"))
                    isSelected = track.equals(name, ignoreCase = true)
                    setOnClickListener { if (!busy) { track = name; loadPreviews(true) } }
                })
            }
            content.addView(HorizontalScrollView(this).apply { addView(row) })
        }
        content.addView(EditText(this).apply {
            id = searchInputId
            hint = getString(R.string.search)
            setSingleLine(true)
            setText(search)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    search = s.toString()
                    ticket++
                    busy = true
                    debounce?.let(handler::removeCallbacks)
                    debounce = Runnable { if (!isDestroyed && screen == "previews" && project != null) loadPreviews(true) }
                    handler.postDelayed(debounce!!, 350)
                }
                override fun afterTextChanged(s: Editable?) {}
            })
        })
        button(R.string.refresh) { loadPreviews(true) }
        if (previews.isEmpty()) text(getString(if (search.isNotBlank() || track != null) R.string.no_filtered_previews else R.string.no_previews))
        previews.forEach { item ->
            val notes = item.string("release_notes").lineSequence().firstOrNull { it.isNotBlank() }?.take(100) ?: ""
            button(listOf(item.string("display_name").ifBlank { getString(R.string.unnamed_app) },
                item.string("version"), item.string("git_commit_sha").take(7), item.string("track"), notes)
                .filter { it.isNotBlank() }.joinToString(" · ")) {
                call("preview", projectArgs().put("id", item.getString("id"))) { data ->
                    detail = data as? JSONObject; render()
                }
            }
        }
        if (hasNext) button(R.string.load_more) { loadPreviews(false) }
    }

    private fun projectArgs() = JSONObject().put("project", project)

    private fun loadTracks() {
        call("tracks", projectArgs(), onFailure = {
            // Older servers have no tracks endpoint; do not invent partial choices or totals.
            tracks = null
            loadPreviews(true)
        }) { data ->
            tracks = (data as? JSONObject)?.takeIf { it.has("total_count") && it.has("tracks") }
            loadPreviews(true)
        }
    }

    private fun loadPreviews(reset: Boolean) {
        debounce?.let(handler::removeCallbacks)
        val nextPage = if (reset) 1 else page + 1
        if (reset) { previews.clear(); hasNext = false; page = 0 }
        call("previews", projectArgs().put("track", track ?: JSONObject.NULL)
            .put("search", search.ifBlank { null } ?: JSONObject.NULL).put("page", nextPage).put("page_size", 20)) { data ->
            val result = data as? JSONObject ?: JSONObject()
            val rows = result.optJSONArray("previews").objects()
            val metadata = result.optJSONObject("pagination_metadata")
            val more = metadata?.optBoolean("has_next_page") ?: false
            val oldIds = if (reset) emptySet() else previews.map { it.optString("id") }.toSet()
            val wrongPage = metadata?.takeIf { it.has("current_page") }?.optInt("current_page")?.let { it != nextPage } ?: false
            val wrongTrack = track != null && rows.any { !it.string("track").equals(track, ignoreCase = true) }
            if (wrongPage || wrongTrack || (more && (rows.isEmpty() || rows.all { it.optString("id") in oldIds }))) {
                hasNext = false; toast(R.string.pagination_failed); render(); return@call
            }
            if (reset) previews.clear()
            previews.addAll(rows.filter { it.optString("id") !in oldIds })
            page = nextPage; hasNext = more; render()
        }
    }

    private fun showDetail(item: JSONObject) {
        button(R.string.back) { detail = null; render() }
        text(item.string("display_name").ifBlank { getString(R.string.unnamed_app) }, 22f)
        val fields = listOf(R.string.preview_version to "version", R.string.bundle_id to "bundle_identifier",
            R.string.branch to "git_branch", R.string.commit to "git_commit_sha", R.string.track to "track",
            R.string.created_at to "inserted_at")
        fields.forEach { (label, key) -> item.string(key).takeIf { it.isNotBlank() }?.let { text(getString(R.string.metadata, getString(label), it)) } }
        item.optJSONArray("supported_platforms")?.let { platforms ->
            text(getString(R.string.metadata, getString(R.string.platforms), (0 until platforms.length()).joinToString(", ") { platforms.optString(it) }))
        }
        item.optJSONObject("created_by")?.string("handle")?.let { text(getString(R.string.metadata, getString(R.string.created_by), it)) }
        if (item.string("release_notes").isNotBlank()) { text(getString(R.string.release_notes), 20f); text(item.string("release_notes")) }
        val platforms = item.optJSONArray("supported_platforms")
        val android = platforms != null && (0 until platforms.length()).any { platforms.optString(it) == "android" }
        val apk = item.optJSONArray("builds").objects().firstOrNull { it.optString("type") == "apk" }
        if (android && apk != null) {
            val url = apk.string("url")
            val uri = Uri.parse(url)
            if (uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null) {
                button(R.string.install) { confirm(R.string.install, R.string.install_message) { open(url) } }
            }
        } else text(getString(R.string.install_unavailable))
        button(R.string.delete_preview) {
            confirm(R.string.delete_preview, R.string.delete_preview_message) {
                call("delete_preview", projectArgs().put("id", item.getString("id"))) { detail = null; loadPreviews(true) }
            }
        }
    }

    private fun confirm(title: Int, message: Int, action: () -> Unit) {
        val generation = view.optLong("generation", -1)
        val profile = view.optString("active_profile_id")
        AlertDialog.Builder(this).setTitle(title).setMessage(message)
            .setPositiveButton(R.string.confirm) { _, _ ->
                if (!busy && generation == view.optLong("generation", -1) && profile == view.optString("active_profile_id")) action()
                else toast(R.string.request_failed)
            }
            .setNegativeButton(R.string.cancel, null).show()
    }

    private fun open(url: String) {
        try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)) }
        catch (_: Exception) { toast(R.string.browser_unavailable) }
    }

    private fun toast(id: Int) { Toast.makeText(this, id, Toast.LENGTH_LONG).show() }
}

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList()
    else (0 until length()).mapNotNull { optJSONObject(it) }

private fun JSONObject.string(key: String): String = if (isNull(key)) "" else optString(key)
