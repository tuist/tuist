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
import android.view.View
import android.view.ViewTreeObserver
import android.widget.EditText
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication
    private lateinit var appearance: AtlasAppearance
    private var baseDark = false
    private var recreating = false
    private var themeRoot: View? = null
    private var themeLayout: ViewTreeObserver.OnGlobalLayoutListener? = null
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
    private var presence: AtlasPresenceModel? = null
    private var people: AtlasPeopleScreen? = null
    private var restorePeople = false
    private var tab = "tasks"
    private var unregisterBack: (() -> Unit)? = null
    private lateinit var router: AtlasDestinationRouter
    private var linkDialog: AlertDialog? = null
    private val authListener: () -> Unit = { render() }

    private data class Retained(
        val authentication: AtlasAuthentication,
        val accounts: AtlasAIAccountsModel?,
        val profile: AtlasProfileModel?,
        val holidays: AtlasTimeOffModel?,
        val navigation: AtlasWorkspaceModel?,
        val businesses: MutableMap<String, AtlasBusinessModel>,
        val tab: String,
        val presence: AtlasPresenceModel?,
        val router: AtlasDestinationRouter,
        val appearance: AtlasAppearance,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        val retained = lastNonConfigurationInstance as? Retained
        appearance = retained?.appearance ?: AtlasAppearance(applicationContext)
        baseDark = appearance.dark
        setTheme(
            if (appearance.mode == "system") {
                R.style.AtlasTheme
            } else if (baseDark) {
                android.R.style.Theme_Material_NoActionBar
            } else {
                android.R.style.Theme_Material_Light_NoActionBar
            },
        )
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)
        authentication = retained?.authentication ?: (application as AtlasApplication).authentication
        accounts = retained?.accounts
        profile = retained?.profile
        holidays = retained?.holidays
        presence = retained?.presence
        router = retained?.router ?: AtlasDestinationRouter()
        businesses = retained?.businesses ?: mutableMapOf()
        tab = retained?.tab ?: savedInstanceState?.getString("tab")?.takeIf { it in tabIds } ?: "tasks"
        navigation = retained?.navigation ?: catalogNavigation(savedInstanceState?.getString("workspace_group"))
        restoreTimeOff = savedInstanceState?.getBoolean("time_off") == true
        restorePeople = savedInstanceState?.getBoolean("people") == true
        recoveredLoginId = if (retained?.accounts == null) savedInstanceState?.getString("chatgpt_login_id") else null
        // Navigation links still need the saved session; only an OAuth callback replaces restoration.
        val data = intent.data?.toString()
        val completingLogin =
            savedInstanceState == null && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0 && isOAuthCallback(data)
        if (retained == null && !completingLogin) authentication.restore()
        if (savedInstanceState == null) handleIntent(intent)
    }

    override fun onRetainNonConfigurationInstance(): Any =
        Retained(authentication, accounts, profile, holidays, navigation, businesses, tab, presence, router, appearance)

    override fun onStart() {
        super.onStart()
        authentication.listener = authListener
        appearance.listener = { appearanceChanged() }
        render()
        presence?.setActive(authentication.server != null)
    }

    override fun onStop() {
        presence?.setActive(false)
        if (authentication.listener === authListener) authentication.listener = null
        appearance.listener = null
        super.onStop()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("workspace_group", navigation?.groupId)
        outState.putString("tab", tab)
        outState.putBoolean("time_off", timeOff != null || restoreTimeOff)
        outState.putBoolean("people", people != null || restorePeople)
        outState.putString("chatgpt_login_id", accounts?.pendingLoginId ?: recoveredLoginId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        closeScreen(cancelPending = !isChangingConfigurations)
        linkDialog?.dismiss()
        unregisterBack?.invoke()
        themeLayout?.let { themeRoot?.viewTreeObserver?.removeOnGlobalLayoutListener(it) }
        if (!isChangingConfigurations) {
            clearModels()
            appearance.close()
        }
        super.onDestroy()
    }

    override fun onContentChanged() {
        super.onContentChanged()
        themeLayout?.let { themeRoot?.viewTreeObserver?.removeOnGlobalLayoutListener(it) }
        val root = findViewById<View>(android.R.id.content)
        themeRoot = root
        val listener = ViewTreeObserver.OnGlobalLayoutListener { appearance.apply(this, root) }
        themeLayout = listener
        root.viewTreeObserver.addOnGlobalLayoutListener(listener)
        appearance.apply(this, root)
    }

    private fun appearanceChanged() {
        if (baseDark != appearance.dark) {
            if (!recreating) {
                recreating = true
                recreate()
            }
            return
        }
        settings?.appearanceChanged()
        themeRoot?.let { appearance.apply(this, it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val data = intent.data?.toString() ?: return
        intent.data = null
        // Reopening Atlas from Recents redelivers the original intent; never replay its link.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (isOAuthCallback(data)) {
            authentication.callback(data)
            return
        }
        val link = AtlasDestination.parse(data, AtlasCore().destinations())
        if (link == null) {
            linkMessage("This Atlas link is invalid or is not supported by this app.")
            return
        }
        router.receive(link)
        // Until the signed-in shell has rendered, render() opens the pending link.
        if (authentication.server != null && presence != null) openPendingLink()
    }

    private fun isOAuthCallback(data: String?): Boolean {
        val uri = data?.let(Uri::parse) ?: return false
        return uri.scheme.equals("dev.tuist.atlas", ignoreCase = true) && uri.host.equals("oauth-callback", ignoreCase = true)
    }

    // Returns true when the link replaced the current screen.
    private fun openPendingLink(): Boolean =
        when (val outcome = router.resolve(authentication.server)) {
            AtlasDestinationRouter.Outcome.None -> false
            AtlasDestinationRouter.Outcome.WrongServer -> {
                linkMessage("This link belongs to a different Atlas server. Sign in to that server and open the link again.")
                false
            }
            is AtlasDestinationRouter.Outcome.Open -> navigate(outcome.destination)
        }

    private fun navigate(destination: AtlasDestination): Boolean {
        if (hasUnsavedWork()) {
            linkMessage("Finish or discard your changes, then open the link again.")
            return false
        }
        closeScreen()
        when (destination.screen) {
            // Browse is the parent of these screens, so Back returns there rather than to the previous tab.
            "time-off" -> {
                tab = "browse"
                showTimeOff(AtlasCore().sections().first { it.screen == "time-off" }.title)
            }
            "people" -> {
                tab = "browse"
                showPeople()
            }
            "profile" -> {
                tab = "profile"
                appearance.showingSettings = false
                showHome()
            }
            else -> {
                tab = destination.screen
                val model = businesses.getOrPut(tab) { AtlasBusinessModel(tab, authentication::business) }
                destination.recordId?.let(model::open) ?: model.showList()
                showHome()
            }
        }
        return true
    }

    // Links never discard a draft, an in-flight save, or an AI provider setup (leaving it cancels ChatGPT sign-in).
    private fun hasUnsavedWork(): Boolean =
        businesses.values.any { it.draft != null || it.saving } ||
            holidays?.let { it.draft != null || it.saving } == true ||
            accounts?.let { it.page != "settings" || it.login != null } == true

    private fun linkMessage(message: String) {
        linkDialog?.dismiss()
        linkDialog =
            AlertDialog
                .Builder(this)
                .setTitle("Couldn’t open link")
                .setMessage(message)
                .setPositiveButton(android.R.string.ok, null)
                .show()
    }

    private fun render() {
        appearance.configure(authentication.server)
        if (recreating) return
        authentication.authorizationURL?.let { url ->
            authentication.authorizationURL = null
            openBrowser(Uri.parse(url))
        }
        if (authentication.server == null) {
            router.resolve(null)
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
        if (presence == null) {
            presence = AtlasPresenceModel(authentication::presence).also { it.setActive(true) }
        }
        if (openPendingLink()) return
        if (home != null || timeOff != null || people != null) return
        if (restorePeople) {
            restorePeople = false
            showPeople()
            return
        }
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
                    presence?.show()
                    val screen =
                        AtlasWorkspaceScreen(this, catalog, Uri.parse(server).host.orEmpty(), { section ->
                            when (section.screen) {
                                "automation" -> startActivity(Intent(this, AtlasAutomationActivity::class.java))
                                "people" -> showPeople()
                                "time-off" -> showTimeOff(section.title)
                                "tasks", "accounts", "invoices" -> selectTab(section.screen)
                            }
                        }, ::updateBack, authentication.errorMessage)
                    workspace = screen
                    setActionBar(screen.toolbar)
                    screen.view
                }
                "profile" -> {
                    presence?.show("profile")
                    val model = accounts ?: AtlasAIAccountsModel(recoveredLoginId, authentication::aiAccounts).also { accounts = it }
                    recoveredLoginId = null
                    val identity = profile ?: AtlasProfileModel(authentication::business).also { profile = it }
                    val screen =
                        AtlasAIAccountsScreen(this, server, model, ::openBrowser, ::back, webPage = { openWebPage("profile") }) {
                            presence?.stop {
                                closeScreen()
                                clearModels()
                                navigation = null
                                tab = "tasks"
                                router.reset()
                                authentication.signOut()
                            }
                        }
                    settings = screen
                    screen.profile(identity, ::updateBack)
                    screen.appearance(appearance)
                    screen.view
                }
                else -> {
                    val model = businesses.getOrPut(tab) { AtlasBusinessModel(tab, authentication::business) }
                    val screen =
                        AtlasBusinessScreen(
                            this,
                            titles.getValue(tab),
                            model,
                            ::updateBack,
                            presence,
                            webPage = { id -> openWebPage(model.resource, id) },
                        )
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
        appearance.showingSettings = false
        closeScreen()
        tab = value
        showHome()
    }

    private fun closeScreen(cancelPending: Boolean = true) {
        people?.close()
        people = null
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
        presence?.setActive(false)
        presence?.listener = null
        presence = null
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
            people != null -> {
                closeScreen()
                showHome()
            }
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
        presence?.show("time_off")
        val model = holidays ?: AtlasTimeOffModel(authentication::timeOff).also { holidays = it }
        val screen = AtlasTimeOffScreen(this, title, model, webPage = { openWebPage("time-off") })
        timeOff = screen
        setActionBar(screen.toolbar)
        setContentView(screen.view)
        updateBack()
        screen.load()
    }

    private fun showPeople() {
        closeScreen()
        val model = presence ?: return
        val screen = AtlasPeopleScreen(this, model, webPage = { openWebPage("people") })
        people = screen
        setActionBar(screen.toolbar)
        setContentView(screen.view)
        updateBack()
    }

    private fun updateBack() {
        if (tab == "profile" && settings != null) {
            presence?.show(if (settings?.isDetail != true) "profile" else null)
        }
        val canUp =
            people != null || timeOff != null || (tab == "profile" && settings?.isDetail == true) ||
                (business != null && businesses[tab]?.canBack == true) || (workspace != null && navigation?.canBack == true)
        actionBar?.setDisplayHomeAsUpEnabled(canUp)
        home?.fullScreen(businesses[tab]?.draft != null || (tab == "profile" && settings?.isDetail == true))
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

    private fun openWebPage(
        screen: String,
        id: String? = null,
    ) {
        val server = authentication.server ?: return
        AtlasDestination.Link(AtlasDestination(screen, id), server).browserURL(AtlasCore().destinations())?.let {
            openAtlasWebPage(it, getString(R.string.no_browser))
        }
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
