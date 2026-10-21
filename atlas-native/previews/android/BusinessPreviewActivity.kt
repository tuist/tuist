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
import dev.tuist.atlas.AtlasHomeScreen
import dev.tuist.atlas.AtlasProfileModel
import dev.tuist.atlas.AtlasWorkspaceModel
import dev.tuist.atlas.AtlasWorkspaceScreen
import org.json.JSONObject

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
                    else -> done(runCatching { fixtures.execute(action) })
                }
            }, if (mutation) 1000 else 100)
        }
    }

    private lateinit var state: State
    private var business: AtlasBusinessScreen? = null
    private var workspace: AtlasWorkspaceScreen? = null
    private var profile: AtlasAIAccountsScreen? = null
    private var home: AtlasHomeScreen? = null
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkBusinessModels()
        state = lastNonConfigurationInstance as? State ?: State(
            intent.getBooleanExtra("fail-save", false),
            intent.getBooleanExtra("permission-denied", false),
        ).apply {
            tab = intent.getStringExtra("tab")?.takeIf { it in listOf("tasks", "accounts", "invoices", "browse", "profile") } ?: "tasks"
        }
        render()
    }

    override fun onRetainNonConfigurationInstance(): Any = state

    override fun onDestroy() {
        close()
        unregisterBack?.invoke()
        super.onDestroy()
    }

    private fun close() {
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
                            if (section.screen == "time-off") {
                                startActivity(android.content.Intent(this, TimeOffPreviewActivity::class.java))
                            } else {
                                choose(section.screen)
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
                    val screen = AtlasAIAccountsScreen(this, "https://atlas.example.org", accounts, {}, { back() }, { finish() })
                    profile = screen
                    screen.profile(identity, ::updateNavigation)
                    screen.view
                }
                else -> {
                    val model = state.models.getOrPut(state.tab) { AtlasBusinessModel(state.tab, state::request) }
                    val screen = AtlasBusinessScreen(this, titles.getValue(state.tab), model, ::updateNavigation, state.fixtures::logo)
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
        if (business?.back() == true || workspace?.back() == true || profile?.back() == true) return true
        if (state.tab != "tasks") {
            choose("tasks")
            return true
        }
        return false
    }

    private fun updateNavigation() {
        val child =
            state.models[state.tab]?.canBack == true || state.navigation?.canBack == true && state.tab == "browse" ||
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
