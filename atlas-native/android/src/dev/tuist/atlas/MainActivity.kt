package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.view.Menu
import android.view.MenuItem
import android.widget.EditText
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication
    private var settings: AtlasAIAccountsScreen? = null
    private var accounts: AtlasAIAccountsModel? = null
    private var holidays: AtlasTimeOffModel? = null
    private var timeOff: AtlasTimeOffScreen? = null
    private var restoreTimeOff = false
    private var navigation: AtlasWorkspaceModel? = null
    private var workspace: AtlasWorkspaceScreen? = null
    private var recoveredLoginId: String? = null

    private data class Retained(
        val authentication: AtlasAuthentication,
        val accounts: AtlasAIAccountsModel?,
        val holidays: AtlasTimeOffModel?,
        val navigation: AtlasWorkspaceModel?,
    )

    private var restoreSettings = false
    private var unregisterSettingsBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)
        val retained = lastNonConfigurationInstance as? Retained
        authentication = retained?.authentication ?: AtlasAuthentication(this)
        accounts = retained?.accounts
        holidays = retained?.holidays
        navigation = retained?.navigation ?: catalogNavigation(savedInstanceState?.getString("workspace_group"))
        restoreTimeOff = savedInstanceState?.getBoolean("time_off") == true
        recoveredLoginId = if (retained?.accounts == null) savedInstanceState?.getString("chatgpt_login_id") else null
        restoreSettings = savedInstanceState?.getBoolean("settings") == true
        if (retained == null && intent.data == null) authentication.restore()
        if (savedInstanceState == null) handleCallback(intent)
    }

    override fun onRetainNonConfigurationInstance(): Any = Retained(authentication, accounts, holidays, navigation)

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
        outState.putBoolean("settings", settings != null || restoreSettings)
        outState.putBoolean("time_off", timeOff != null || restoreTimeOff)
        outState.putString("chatgpt_login_id", accounts?.pendingLoginId ?: recoveredLoginId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        settings?.close(cancelPending = !isChangingConfigurations)
        timeOff?.close()
        workspace?.close()
        if (!isChangingConfigurations && settings == null) accounts?.takeIf { it.pendingLoginId != null }?.load()
        unregisterSettingsBack?.invoke()
        if (!isChangingConfigurations) authentication.close()
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
        invalidateOptionsMenu()
        if (authentication.server == null) {
            settings?.close()
            settings = null
            accounts = null
            timeOff?.close()
            timeOff = null
            holidays = null
            workspace?.close()
            workspace = null
            if (!authentication.busy) {
                restoreTimeOff = false
                navigation = null
            }
            updateSettingsBack()
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
        if (settings != null || timeOff != null) return
        if (restoreTimeOff) {
            restoreTimeOff = false
            showTimeOff(AtlasCore().sections().first { it.screen == "time-off" }.title)
            return
        }
        if (restoreSettings) {
            restoreSettings = false
            showSettings()
            return
        }
        val server = authentication.server ?: return
        val model = navigation ?: catalogNavigation().also { navigation = it }
        workspace?.close()
        val screen =
            AtlasWorkspaceScreen(this, model, Uri.parse(server).host.orEmpty(), { section ->
                if (section.screen == "time-off") {
                    showTimeOff(section.title)
                } else {
                    openBrowser(section.destination(server))
                }
            }, {
                actionBar?.setDisplayHomeAsUpEnabled(model.canBack)
                updateSettingsBack()
            }, authentication.errorMessage)
        workspace = screen
        setActionBar(screen.toolbar)
        actionBar?.setDisplayHomeAsUpEnabled(model.canBack)
        setContentView(screen.view)
        updateSettingsBack()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, 1, 0, "Settings").apply {
            setIcon(android.R.drawable.ic_menu_preferences)
            setShowAsAction(MenuItem.SHOW_AS_ACTION_IF_ROOM)
        }
        return true
    }

    override fun onPrepareOptionsMenu(menu: Menu): Boolean {
        menu.findItem(1)?.isVisible = authentication.server != null && settings == null && timeOff == null
        return super.onPrepareOptionsMenu(menu)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean =
        when (item.itemId) {
            1 -> {
                showSettings()
                true
            }
            android.R.id.home -> {
                if (timeOff != null) {
                    leaveTimeOff()
                } else if (settings != null) {
                    leaveSettings()
                } else {
                    workspace?.back()
                }
                true
            }
            else -> super.onOptionsItemSelected(item)
        }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (timeOff != null) {
            leaveTimeOff()
        } else if (settings != null) {
            leaveSettings()
        } else if (workspace?.back() != true) {
            super.onBackPressed()
        }
    }

    private fun catalogNavigation(group: String? = null): AtlasWorkspaceModel {
        val core = AtlasCore()
        return AtlasWorkspaceModel(core.groups(), core.sections(), group)
    }

    private fun showTimeOff(title: String) {
        val model = holidays ?: AtlasTimeOffModel(authentication::timeOff).also { holidays = it }
        val screen = AtlasTimeOffScreen(this, title, model)
        timeOff = screen
        setActionBar(screen.toolbar)
        actionBar?.setDisplayHomeAsUpEnabled(true)
        setContentView(screen.view)
        invalidateOptionsMenu()
        updateSettingsBack()
        screen.load()
    }

    private fun leaveTimeOff() {
        if (timeOff?.back() == true) return
        timeOff?.close()
        timeOff = null
        updateSettingsBack()
        render()
    }

    private fun showSettings() {
        val server = authentication.server ?: return
        val model = accounts ?: AtlasAIAccountsModel(recoveredLoginId, authentication::aiAccounts)
        accounts = model
        recoveredLoginId = null
        val screen =
            AtlasAIAccountsScreen(this, server, model, ::openBrowser, ::leaveSettings) {
                settings?.close()
                settings = null
                accounts = null
                updateSettingsBack()
                actionBar?.setDisplayHomeAsUpEnabled(false)
                authentication.signOut()
            }
        settings = screen
        updateSettingsBack()
        actionBar?.setDisplayHomeAsUpEnabled(true)
        invalidateOptionsMenu()
        setContentView(screen.view)
        screen.load()
    }

    private fun leaveSettings() {
        if (settings?.back() == true) return
        settings?.close()
        settings = null
        updateSettingsBack()
        actionBar?.setDisplayHomeAsUpEnabled(false)
        render()
    }

    private fun updateSettingsBack() {
        unregisterSettingsBack?.invoke()
        unregisterSettingsBack = null
        if (Build.VERSION.SDK_INT >= 33 &&
            (settings != null || timeOff != null || (authentication.server != null && navigation?.canBack == true))
        ) {
            val callback =
                OnBackInvokedCallback {
                    if (timeOff != null) {
                        leaveTimeOff()
                    } else if (settings != null) {
                        leaveSettings()
                    } else {
                        workspace?.back()
                    }
                }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterSettingsBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
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
}
