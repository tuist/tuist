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
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import android.widget.Toolbar
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication
    private var settings: AtlasAIAccountsScreen? = null
    private var accounts: AtlasAIAccountsModel? = null
    private var holidays: AtlasTimeOffModel? = null
    private var timeOff: AtlasTimeOffScreen? = null
    private var restoreTimeOff = false
    private var recoveredLoginId: String? = null

    private data class Retained(
        val authentication: AtlasAuthentication,
        val accounts: AtlasAIAccountsModel?,
        val holidays: AtlasTimeOffModel?,
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
        restoreTimeOff = savedInstanceState?.getBoolean("time_off") == true
        recoveredLoginId = if (retained?.accounts == null) savedInstanceState?.getString("chatgpt_login_id") else null
        restoreSettings = savedInstanceState?.getBoolean("settings") == true
        if (retained == null && intent.data == null) authentication.restore()
        if (savedInstanceState == null) handleCallback(intent)
    }

    override fun onRetainNonConfigurationInstance(): Any = Retained(authentication, accounts, holidays)

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
        outState.putBoolean("settings", settings != null || restoreSettings)
        outState.putBoolean("time_off", timeOff != null || restoreTimeOff)
        outState.putString("chatgpt_login_id", accounts?.pendingLoginId ?: recoveredLoginId)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        settings?.close(cancelPending = !isChangingConfigurations)
        timeOff?.close()
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
            if (!authentication.busy) restoreTimeOff = false
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
        title = getString(R.string.app_name)
        val content =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val padding = (24 * resources.displayMetrics.density).toInt()
                setPadding(padding, padding, padding, padding)
            }
        content.addView(
            TextView(this).apply {
                text = getString(R.string.welcome)
                textSize = 28f
                setPadding(0, 0, 0, 24)
            },
        )

        fun button(
            label: String,
            action: () -> Unit,
        ) {
            content.addView(
                Button(this).apply {
                    text = label
                    isEnabled = !authentication.busy
                    setOnClickListener { action() }
                },
            )
        }
        val server = authentication.server
        if (server != null) {
            content.addView(TextView(this).apply { text = Uri.parse(server).host })
            AtlasCore()
                .sections()
                .filter {
                    !Uri
                        .parse(it.url)
                        .path
                        .orEmpty()
                        .startsWith("/settings/")
                }.forEach { section ->
                    button(section.title) {
                        if (section.screen == "time-off") {
                            showTimeOff(section.title)
                            return@button
                        }
                        val origin = Uri.parse(server)
                        val destination =
                            Uri
                                .parse(
                                    section.url,
                                ).buildUpon()
                                .scheme(origin.scheme)
                                .encodedAuthority(origin.encodedAuthority)
                                .build()
                        openBrowser(destination)
                    }
                    content.addView(
                        TextView(this).apply {
                            text = section.description
                            textSize = 16f
                            setPadding(0, 0, 0, 32)
                        },
                    )
                }
            content.addView(
                TextView(this).apply {
                    text = "Other workspace sections open in your browser, which may ask you to sign in separately."
                },
            )
        }
        if (authentication.busy) content.addView(TextView(this).apply { text = "Updating session…" })
        authentication.errorMessage?.let { message -> content.addView(TextView(this).apply { text = message }) }
        val toolbar = Toolbar(this)
        setActionBar(toolbar)
        val scroll =
            ScrollView(this).apply {
                addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setOnApplyWindowInsetsListener { view, insets ->
                    view.setPadding(insets.systemWindowInsetLeft, insets.systemWindowInsetTop, insets.systemWindowInsetRight, 0)
                    scroll.setPadding(0, 0, 0, insets.systemWindowInsetBottom)
                    insets
                }
                addView(toolbar, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
                addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
            },
        )
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
                if (timeOff != null) leaveTimeOff() else leaveSettings()
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
        } else {
            super.onBackPressed()
        }
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
        if (Build.VERSION.SDK_INT >= 33 && (settings != null || timeOff != null)) {
            val callback = OnBackInvokedCallback { if (timeOff != null) leaveTimeOff() else leaveSettings() }
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
