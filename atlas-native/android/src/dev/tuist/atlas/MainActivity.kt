package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.MenuItem
import android.widget.EditText
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication
    private var settings: AtlasAIAccountsScreen? = null
    private var accounts: AtlasAIAccountsModel? = null
    private var profile: AtlasProfileModel? = null
    private var holidays: AtlasTimeOffModel? = null
    private var timeOff: AtlasTimeOffScreen? = null
    private var restoreTimeOff = false
    private var navigation: AtlasWorkspaceModel? = null
    private var workspace: AtlasWorkspaceScreen? = null
    private var recoveredLoginId: String? = null
    private var businesses = mutableMapOf<String, AtlasBusinessModel>()
    private var business: AtlasBusinessScreen? = null
    private var home: AtlasHomeScreen? = null
    private var tab = "tasks"
    private var unregisterBack: (() -> Unit)? = null

    private data class Retained(
        val authentication: AtlasAuthentication,
        val accounts: AtlasAIAccountsModel?,
        val profile: AtlasProfileModel?,
        val holidays: AtlasTimeOffModel?,
        val navigation: AtlasWorkspaceModel?,
        val businesses: MutableMap<String, AtlasBusinessModel>,
        val tab: String,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)
        val retained = lastNonConfigurationInstance as? Retained
        authentication = retained?.authentication ?: AtlasAuthentication(this)
        accounts = retained?.accounts
        profile = retained?.profile
        holidays = retained?.holidays
        businesses = retained?.businesses ?: mutableMapOf()
        tab = retained?.tab ?: savedInstanceState?.getString("tab")?.takeIf { it in tabIds } ?: "tasks"
        navigation = retained?.navigation ?: catalogNavigation(savedInstanceState?.getString("workspace_group"))
        restoreTimeOff = savedInstanceState?.getBoolean("time_off") == true
        recoveredLoginId = if (retained?.accounts == null) savedInstanceState?.getString("chatgpt_login_id") else null
        if (retained == null && intent.data == null) authentication.restore()
        if (savedInstanceState == null) handleCallback(intent)
    }

    override fun onRetainNonConfigurationInstance(): Any =
        Retained(authentication, accounts, profile, holidays, navigation, businesses, tab)

    override fun onStart() {
        super.onStart()
        authentication.listener = { render() }
        render()
    }

    override fun onStop() {
        authentication.listener = null
        super.onStop()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("workspace_group", navigation?.groupId)
        outState.putString("tab", tab)
        outState.putBoolean("time_off", timeOff != null || restoreTimeOff)
        outState.putString("chatgpt_login_id", accounts?.pendingLoginId ?: recoveredLoginId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        closeScreen(cancelPending = !isChangingConfigurations)
        unregisterBack?.invoke()
        if (!isChangingConfigurations) {
            clearModels()
            authentication.close()
        }
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleCallback(intent)
    }

    private fun handleCallback(intent: Intent) {
        val callback = intent.data ?: return
        intent.data = null
        authentication.callback(callback.toString())
    }

    private fun render() {
        authentication.authorizationURL?.let { url ->
            authentication.authorizationURL = null
            openBrowser(Uri.parse(url))
        }
        if (authentication.server == null) {
            closeScreen()
            clearModels()
            if (!authentication.busy) {
                restoreTimeOff = false
                navigation = null
                tab = "tasks"
            }
            updateBack()
            setActionBar(null)
            setContentView(
                AtlasLoginView(
                    this,
                    authentication.busy,
                    authentication.errorMessage,
                    hosted = { authentication.signIn("https://atlas.tuist.dev", false) },
                    selfHosted = { selfHostedPrompt() },
                ),
            )
            return
        }
        if (home != null || timeOff != null) return
        if (restoreTimeOff) {
            restoreTimeOff = false
            showTimeOff(AtlasCore().sections().first { it.screen == "time-off" }.title)
            return
        }
        showHome()
    }

    private fun showHome() {
        val server = authentication.server ?: return
        val catalog = navigation ?: catalogNavigation().also { navigation = it }
        val titles =
            linkedMapOf(
                "tasks" to catalog.sections.first { it.screen == "tasks" }.title,
                "accounts" to catalog.sections.first { it.screen == "accounts" }.title,
                "invoices" to catalog.groups.first { it.id == "finance" }.title,
                "browse" to "Browse",
                "profile" to "Profile",
            )
        val content =
            when (tab) {
                "browse" -> {
                    val screen =
                        AtlasWorkspaceScreen(this, catalog, Uri.parse(server).host.orEmpty(), { section ->
                            when (section.screen) {
                                "time-off" -> showTimeOff(section.title)
                                "tasks", "accounts", "invoices" -> selectTab(section.screen)
                            }
                        }, ::updateBack, authentication.errorMessage)
                    workspace = screen
                    setActionBar(screen.toolbar)
                    screen.view
                }
                "profile" -> {
                    val model = accounts ?: AtlasAIAccountsModel(recoveredLoginId, authentication::aiAccounts).also { accounts = it }
                    recoveredLoginId = null
                    val identity = profile ?: AtlasProfileModel(authentication::business).also { profile = it }
                    val screen =
                        AtlasAIAccountsScreen(this, server, model, ::openBrowser, ::back) {
                            closeScreen()
                            clearModels()
                            navigation = null
                            tab = "tasks"
                            authentication.signOut()
                        }
                    settings = screen
                    screen.profile(identity, ::updateBack)
                    screen.view
                }
                else -> {
                    val model = businesses.getOrPut(tab) { AtlasBusinessModel(tab, authentication::business) }
                    val screen = AtlasBusinessScreen(this, titles.getValue(tab), model, ::updateBack)
                    business = screen
                    setActionBar(screen.toolbar)
                    screen.view
                }
            }
        val shell = AtlasHomeScreen(this, content, titles, tab, ::selectTab)
        home = shell
        setContentView(shell.view)
        updateBack()
        business?.load()
        settings?.load()
    }

    private fun selectTab(value: String) {
        if (value == tab || value !in tabIds || businesses[tab]?.saving == true) return
        closeScreen()
        tab = value
        showHome()
    }

    private fun closeScreen(cancelPending: Boolean = true) {
        settings?.close(cancelPending)
        settings = null
        timeOff?.close()
        timeOff = null
        business?.close()
        business = null
        workspace?.close()
        workspace = null
        home = null
    }

    private fun clearModels() {
        businesses.values.forEach { it.clear() }
        businesses.clear()
        profile?.clear()
        profile = null
        accounts = null
        holidays = null
        recoveredLoginId = null
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        if (item.itemId != android.R.id.home) return super.onOptionsItemSelected(item)
        back()
        return true
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!back()) super.onBackPressed()
    }

    private fun back(): Boolean {
        when {
            timeOff != null -> {
                if (timeOff?.back() != true) {
                    closeScreen()
                    showHome()
                }
            }
            settings?.back() == true -> Unit
            business?.back() == true -> Unit
            workspace?.back() == true -> Unit
            authentication.server != null && tab != "tasks" -> selectTab("tasks")
            else -> return false
        }
        updateBack()
        return true
    }

    private fun catalogNavigation(group: String? = null): AtlasWorkspaceModel {
        val core = AtlasCore()
        return AtlasWorkspaceModel(core.groups(), core.sections(), group)
    }

    private fun showTimeOff(title: String) {
        closeScreen()
        val model = holidays ?: AtlasTimeOffModel(authentication::timeOff).also { holidays = it }
        val screen = AtlasTimeOffScreen(this, title, model)
        timeOff = screen
        setActionBar(screen.toolbar)
        setContentView(screen.view)
        updateBack()
        screen.load()
    }

    private fun updateBack() {
        val canUp =
            timeOff != null || (tab == "profile" && accounts?.page != "settings") ||
                (business != null && businesses[tab]?.canBack == true) || (workspace != null && navigation?.canBack == true)
        actionBar?.setDisplayHomeAsUpEnabled(canUp)
        home?.fullScreen(businesses[tab]?.draft != null || (tab == "profile" && accounts?.page != "settings"))
        unregisterBack?.invoke()
        unregisterBack = null
        if (Build.VERSION.SDK_INT >= 33 && authentication.server != null && (canUp || tab != "tasks")) {
            val callback = OnBackInvokedCallback { back() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
    }

    private fun selfHostedPrompt() {
        val field =
            EditText(this).apply {
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                hint = "https://atlas.example.com"
                setText(authentication.selfHostedAddress)
            }
        AlertDialog
            .Builder(this)
            .setTitle("Self-hosted server")
            .setView(field)
            .setPositiveButton("Sign in") { _, _ -> authentication.signIn(field.text.toString(), true) }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun openBrowser(uri: Uri) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).apply { addCategory(Intent.CATEGORY_BROWSABLE) })
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(this, R.string.no_browser, Toast.LENGTH_LONG).show()
        }
    }

    companion object {
        private val tabIds = setOf("tasks", "accounts", "invoices", "browse", "profile")
    }
}
