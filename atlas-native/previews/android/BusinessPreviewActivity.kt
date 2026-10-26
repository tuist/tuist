package dev.tuist.atlas.preview

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MenuItem
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import dev.tuist.atlas.AtlasAIAccountsModel
import dev.tuist.atlas.AtlasAIAccountsScreen
import dev.tuist.atlas.AtlasBusinessModel
import dev.tuist.atlas.AtlasBusinessScreen
import dev.tuist.atlas.AtlasCore
import dev.tuist.atlas.AtlasDestination
import dev.tuist.atlas.AtlasDestinationRouter
import dev.tuist.atlas.AtlasHomeScreen
import dev.tuist.atlas.AtlasPeopleScreen
import dev.tuist.atlas.AtlasPresenceModel
import dev.tuist.atlas.AtlasProfileModel
import dev.tuist.atlas.AtlasWorkspaceModel
import dev.tuist.atlas.AtlasWorkspaceScreen
import dev.tuist.atlas.AuthFailure
import org.json.JSONObject

// Preview-only: this UUID resolves to the first fixture record of each resource; other UUIDs are unavailable.
private const val PREVIEW_RECORD = "00000000-0000-4000-8000-000000000001"
private const val PREVIEW_SERVER = "https://atlas.example.org/"

class BusinessPreviewActivity : Activity() {
    private class State(
        val failSave: Boolean,
        val permissionDenied: Boolean,
    ) {
        val fixtures = AtlasBusinessFixtures()
        val models = mutableMapOf<String, AtlasBusinessModel>()
        var tab = "tasks"
        var navigation: AtlasWorkspaceModel? = null
        var profile: AtlasProfileModel? = null
        var accounts: AtlasAIAccountsModel? = null
        val router = AtlasDestinationRouter()
        private var sequence = 1L
        private var waiting: ((Result<JSONObject>) -> Unit)? = null
        val presence =
            AtlasPresenceModel { action, done ->
                when (action.getString("action")) {
                    "open" -> done(Result.success(JSONObject().put("connection", "preview-only")))
                    "next" -> {
                        if (action.getLong("after") < sequence) {
                            done(Result.success(snapshot()))
                        } else {
                            waiting = done
                        }
                    }
                    "update" -> {
                        sequence += 1
                        val completion = waiting
                        waiting = null
                        completion?.invoke(Result.success(snapshot()))
                        done(Result.success(JSONObject().put("updated", true)))
                    }
                    else -> {
                        val completion = waiting
                        waiting = null
                        completion?.invoke(Result.success(snapshot()))
                        done(Result.success(JSONObject().put("closed", true)))
                    }
                }
            }

        private fun snapshot() =
            JSONObject(
                """{"location":{"resource":"people"},"people":[
                {"id":"online","name":"Alex Morgan","email":"alex@example.org","online":true,"here":true},
                {"id":"offline","name":"Sam Rivera","email":"sam@example.org","online":false,"here":false}]}""",
            ).put("sequence", sequence)

        fun execute(action: JSONObject): JSONObject {
            if (!action.has("id")) return fixtures.execute(action)
            val alias = action.getString("id") == PREVIEW_RECORD
            val lookup =
                if (alias) {
                    JSONObject(
                        action.toString(),
                    ).put("id", "${action.getString("resource").removeSuffix("s")}-1")
                } else {
                    action
                }
            val response =
                try {
                    fixtures.execute(lookup)
                } catch (_: NoSuchElementException) {
                    throw AuthFailure("unavailable", "This item is no longer available. Refresh the list.")
                }
            val item = response.optJSONObject("item")
            return if (alias && item != null) JSONObject().put("item", JSONObject(item.toString()).put("id", PREVIEW_RECORD)) else response
        }

        fun request(
            action: JSONObject,
            done: (Result<JSONObject>) -> Unit,
        ) {
            val mutation = action.optString("action") !in listOf("list", "show")
            Handler(Looper.getMainLooper()).postDelayed({
                when {
                    permissionDenied && action.getString("resource") == "invoices" ->
                        done(Result.failure(IllegalStateException("You do not have permission to view Finance.")))
                    mutation && failSave ->
                        done(Result.failure(IllegalStateException("Preview save failed. Your draft is still here.")))
                    else -> done(runCatching { execute(action) })
                }
            }, if (mutation) 1000 else 100)
        }
    }

    private lateinit var state: State
    private var linkDialog: android.app.AlertDialog? = null
    private var business: AtlasBusinessScreen? = null
    private var workspace: AtlasWorkspaceScreen? = null
    private var profile: AtlasAIAccountsScreen? = null
    private var home: AtlasHomeScreen? = null
    private var people: AtlasPeopleScreen? = null
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkBusinessModels()
        checkPresenceModel()
        checkOrbitModel()
        checkDestinations()
        val retained = lastNonConfigurationInstance as? State
        state = retained ?: State(
            intent.getBooleanExtra("fail-save", false),
            intent.getBooleanExtra("permission-denied", false),
        ).apply {
            tab = intent.getStringExtra("tab")?.takeIf { it in listOf("tasks", "accounts", "invoices", "browse", "profile") } ?: "tasks"
        }
        val link = intent.getStringExtra("link")?.takeIf { retained == null && savedInstanceState == null }
        if (link == null || !openLink(link)) render()
    }

    // Routes `--es link <url>` through the production parser, router, and models against the fixture server.
    private fun openLink(value: String): Boolean {
        val link = AtlasDestination.parse(value, AtlasCore().destinations())
        if (link == null) {
            message("This Atlas link is invalid or is not supported by this app.")
            return false
        }
        state.router.receive(link)
        val outcome = state.router.resolve(PREVIEW_SERVER)
        if (outcome !is AtlasDestinationRouter.Outcome.Open) {
            message("This link belongs to a different Atlas server. Sign in to that server and open the link again.")
            return false
        }
        val destination = outcome.destination
        when (destination.screen) {
            "time-off" -> {
                startActivity(android.content.Intent(this, TimeOffPreviewActivity::class.java))
                return false
            }
            "people" -> {
                showPeople()
                return true
            }
            "profile" -> state.tab = "profile"
            else -> {
                state.tab = destination.screen
                val model = state.models.getOrPut(state.tab) { AtlasBusinessModel(state.tab, state::request) }
                destination.recordId?.let(model::open) ?: model.showList()
            }
        }
        render()
        return true
    }

    private fun message(text: String) {
        linkDialog =
            android.app.AlertDialog
                .Builder(this)
                .setTitle("Couldn’t open link")
                .setMessage(text)
                .setPositiveButton(android.R.string.ok, null)
                .show()
    }

    private fun showPeople() {
        close()
        val screen = AtlasPeopleScreen(this, state.presence)
        people = screen
        setActionBar(screen.toolbar)
        setContentView(screen.view)
        state.presence.setActive(true)
        updateNavigation()
    }

    override fun onRetainNonConfigurationInstance(): Any = state

    override fun onDestroy() {
        close()
        linkDialog?.dismiss()
        if (!isChangingConfigurations) state.presence.setActive(false)
        unregisterBack?.invoke()
        super.onDestroy()
    }

    private fun close() {
        people?.close()
        people = null
        business?.close()
        business = null
        workspace?.close()
        workspace = null
        profile?.close(cancelPending = false)
        profile = null
    }

    private fun render() {
        val core = AtlasCore()
        val catalog = state.navigation ?: AtlasWorkspaceModel(core.groups(), core.sections()).also { state.navigation = it }
        val titles =
            linkedMapOf(
                "tasks" to core.sections().first { it.id == "tasks" }.title,
                "accounts" to core.sections().first { it.id == "accounts" }.title,
                "invoices" to core.groups().first { it.id == "finance" }.title,
                "browse" to "Browse",
                "profile" to "Profile",
            )
        val content =
            when (state.tab) {
                "browse" -> {
                    val screen =
                        AtlasWorkspaceScreen(this, catalog, "atlas.example.org", { section ->
                            when (section.screen) {
                                "time-off" -> startActivity(android.content.Intent(this, TimeOffPreviewActivity::class.java))
                                "people" -> showPeople()
                                else -> choose(section.screen)
                            }
                        }, ::updateNavigation)
                    workspace = screen
                    setActionBar(screen.toolbar)
                    screen.view
                }
                "profile" -> {
                    val identity = state.profile ?: AtlasProfileModel(state::request).also { state.profile = it }
                    val accounts =
                        state.accounts ?: AtlasAIAccountsModel { _, done ->
                            done(
                                Result.success(
                                    JSONObject(
                                        """{"providers":[{"provider":"claude","credential_configured":false},{"provider":"chatgpt","credential_configured":false,"login_available":false}]}""",
                                    ),
                                ),
                            )
                        }.also { state.accounts = it }
                    val screen = AtlasAIAccountsScreen(this, "https://atlas.example.org", accounts, {}, { back() }, signOut = { finish() })
                    profile = screen
                    screen.profile(identity, ::updateNavigation)
                    screen.view
                }
                else -> {
                    val model = state.models.getOrPut(state.tab) { AtlasBusinessModel(state.tab, state::request) }
                    val screen =
                        AtlasBusinessScreen(this, titles.getValue(state.tab), model, ::updateNavigation, logoLoader = state.fixtures::logo)
                    business = screen
                    setActionBar(screen.toolbar)
                    screen.view
                }
            }
        home = AtlasHomeScreen(this, content, titles, state.tab, ::choose)
        setContentView(home!!.view)
        updateNavigation()
        business?.load()
        profile?.load()
    }

    private fun choose(tab: String) {
        if (tab == state.tab || state.models[state.tab]?.saving == true) return
        close()
        state.tab = tab
        render()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!back()) super.onBackPressed()
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId != android.R.id.home) return super.onOptionsItemSelected(item)
        back()
        return true
    }

    private fun back(): Boolean {
        if (people != null) {
            close()
            render()
            return true
        }
        if (business?.back() == true || workspace?.back() == true || profile?.back() == true) return true
        if (state.tab != "tasks") {
            choose("tasks")
            return true
        }
        return false
    }

    private fun updateNavigation() {
        val child =
            people != null || state.models[state.tab]?.canBack == true || state.navigation?.canBack == true && state.tab == "browse" ||
                state.tab == "profile" && state.accounts?.page != "settings"
        actionBar?.setDisplayHomeAsUpEnabled(child)
        home?.fullScreen(state.models[state.tab]?.draft != null || state.tab == "profile" && state.accounts?.page != "settings")
        unregisterBack?.invoke()
        unregisterBack = null
        if (Build.VERSION.SDK_INT >= 33 && (child || state.tab != "tasks")) {
            val callback = OnBackInvokedCallback { back() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
    }
}
