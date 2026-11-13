package dev.tuist.code

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.TextWatcher
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.HorizontalScrollView
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
    private var screen = "previews"
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
    private val searchInputId = View.generateViewId()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        host = AppHost(applicationContext)
        screen = savedInstanceState?.getString("screen") ?: "previews"
        call("snapshot") {
            render()
            if (!callback(intent)) {
                if (AppCore.pendingAuthorization != null) launchPendingSignIn()
                else if (active() != null && screen == "previews") loadProjects()
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("screen", screen)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        callback(intent)
    }

    override fun onDestroy() {
        ticket++
        handler.removeCallbacksAndMessages(null)
        if (browserPending && isFinishing && !isChangingConfigurations) {
            AppCore.submit("cancel_sign_in", JSONObject(), host) { }
        }
        super.onDestroy()
    }

    private fun callback(intent: Intent): Boolean {
        val uri = intent.data ?: return false
        intent.data = null
        if (uri.scheme != "tuist-code" || uri.host != "oauth-callback" || !uri.path.isNullOrEmpty()) return false
        browserPending = false
        call("finish_sign_in", JSONObject().put("url", uri.toString())) { reset(); render(); loadProjects() }
        return true
    }

    private fun call(operation: String, args: JSONObject = JSONObject(), onFailure: (() -> Unit)? = null,
                     done: (Any?) -> Unit = { render() }) {
        val requestTicket = ++ticket
        val generation = view.optLong("generation", -1)
        busy = true
        AppCore.submit(operation, args, host) { result ->
            runOnUiThread {
                if (isDestroyed || requestTicket != ticket) return@runOnUiThread
                busy = false
                val next = result.optJSONObject("view")
                if (next != null && next.optLong("generation", -1) < generation) return@runOnUiThread
                if (next != null) view = next
                if (!result.isNull("error") && result.optString("error").isNotBlank()) {
                    if (operation == "begin_sign_in") browserPending = false
                    if (onFailure != null) { onFailure(); return@runOnUiThread }
                    // Backend and OAuth error text can contain credentials; expose only localized copy.
                    toast(R.string.request_failed)
                    render()
                    return@runOnUiThread
                }
                done(result.opt("data"))
            }
        }
    }

    private fun active(): JSONObject? = view.optJSONArray("profiles").objects()
        .firstOrNull { it.optString("id") == view.optString("active_profile_id") }

    private fun reset() {
        debounce?.let(handler::removeCallbacks)
        project = null; track = null; search = ""; page = 0
        projects = emptyList(); previews.clear(); tracks = null; detail = null
    }

    private fun render() {
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
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        root.addView(ScrollView(this).apply { addView(content) }, LinearLayout.LayoutParams(-1, 0, 1f))
        text(getString(if (screen == "profile") R.string.profile else R.string.previews), 28f)
        if (busy) text(getString(R.string.loading))
        if (screen == "profile") profileScreen() else previewScreen()
        root.addView(Button(this).apply {
            setText(R.string.previews)
            setOnClickListener {
                if (!busy && !browserPending) { screen = "previews"; render(); if (projects.isEmpty()) loadProjects() }
            }
        })
        root.addView(Button(this).apply {
            setText(R.string.profile)
            setOnClickListener {
                if (!busy) {
                    if (screen == "profile" && !browserPending) chooseProfile()
                    else { screen = "profile"; render() }
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

    private fun text(value: String, size: Float = 16f) {
        content.addView(TextView(this).apply { text = value; textSize = size; setPadding(0, 8, 0, 8) })
    }

    private fun button(label: Int, action: () -> Unit) = button(getString(label), action)
    private fun button(label: String, action: () -> Unit) {
        content.addView(Button(this).apply {
            text = label
            setOnClickListener { if (!busy) action() }
        })
    }

    private fun profileScreen() {
        active()?.let { profile ->
            text("@${profile.optString("handle")}", 22f)
            text(profile.optString("email"))
            text(profile.optString("server"))
            if (profile.optBoolean("rejected")) text(getString(R.string.sign_in_required))
            val organization = profile.opt("organization")
            if (organization is JSONObject) text(organization.optString("name"))
            else if (organization is String) text(organization)
            if (!browserPending) button(R.string.organizations) {
                call("organizations") {
                    val refreshed = active()?.takeUnless { it.optBoolean("rejected") } ?: return@call
                    val organizations = refreshed.optJSONArray("organizations") ?: JSONArray()
                    val items = listOf(refreshed.getString("handle")) +
                        (0 until organizations.length()).map { organizations.getString(it) }
                    AlertDialog.Builder(this).setTitle(R.string.organizations)
                        .setItems(items.toTypedArray()) { _, i ->
                            call("select_organization", JSONObject().put("id", refreshed.getString("id"))
                                .put("name", items[i])) { reset(); render() }
                        }.setNegativeButton(R.string.cancel, null).show()
                }
            }
        } ?: text(getString(R.string.sign_in_required))
        if (!browserPending) button(R.string.switch_profile) { chooseProfile() }
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
        if (active() != null && !browserPending) {
            button(R.string.sign_out) { call("sign_out") { reset(); render() } }
            button(R.string.delete_account) {
                confirm(R.string.delete_account, R.string.delete_account_message) {
                    call("delete_account") { reset(); render() }
                }
            }
        }
    }

    private fun chooseProfile() {
        val profiles = view.optJSONArray("profiles").objects()
        AlertDialog.Builder(this).setTitle(R.string.switch_profile)
            .setItems((profiles.map { "@${it.optString("handle")} · ${it.optString("server")}" } + getString(R.string.add_profile)).toTypedArray()) { _, i ->
                if (i == profiles.size) signIn()
                else call("switch_profile", JSONObject().put("id", profiles[i].getString("id"))) {
                    reset(); render(); if (screen == "previews") loadProjects()
                }
            }.setNegativeButton(R.string.cancel, null).show()
    }

    private fun signIn() {
        val input = EditText(this).apply {
            hint = getString(R.string.server_url)
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
            setText(active()?.optString("server") ?: "https://tuist.dev")
        }
        AlertDialog.Builder(this).setTitle(R.string.add_profile).setView(input)
            .setPositiveButton(R.string.continue_label) { _, _ ->
                val server = input.text.toString().trim()
                val uri = Uri.parse(server)
                if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) {
                    toast(R.string.https_required); return@setPositiveButton
                }
                val providers = arrayOf("tuist", "github", "google", "apple")
                AlertDialog.Builder(this).setTitle(R.string.provider)
                    .setItems(arrayOf(getString(R.string.provider_tuist), getString(R.string.provider_github),
                        getString(R.string.provider_google), getString(R.string.provider_apple))) { _, index ->
                        launchSignIn(server, providers[index])
                    }.setNegativeButton(R.string.cancel, null).show()
            }.setNegativeButton(R.string.cancel, null).show()
    }

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
        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null || payload.optString("callback_scheme") != "tuist-code") {
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
            screen = "profile"
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

    private fun projectName(item: JSONObject): String = item.optString("full_name").ifBlank {
        item.optString("full_handle").ifBlank { item.optString("name") }
    }

    private fun previewScreen() {
        if (active() == null) { button(R.string.add_profile) { signIn() }; return }
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
