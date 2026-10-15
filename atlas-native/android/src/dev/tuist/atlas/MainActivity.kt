package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
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

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication
    private var settings: AtlasAIAccountsScreen? = null
    private var restoreSettings = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)
        authentication = (lastNonConfigurationInstance as? AtlasAuthentication) ?: AtlasAuthentication(this)
        restoreSettings = savedInstanceState?.getBoolean("settings") == true
        if (lastNonConfigurationInstance == null && intent.data == null) authentication.restore()
        if (savedInstanceState == null) handleCallback(intent)
    }

    override fun onRetainNonConfigurationInstance(): Any = authentication

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
        outState.putBoolean("settings", settings != null)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        settings?.close()
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
            actionBar?.setDisplayHomeAsUpEnabled(false)
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
        if (settings != null) return
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
                    text = "Sections currently open in your browser, which may ask you to sign in separately."
                },
            )
            button("Settings") { showSettings() }
        }
        if (authentication.busy) content.addView(TextView(this).apply { text = "Signing in…" })
        authentication.errorMessage?.let { message -> content.addView(TextView(this).apply { text = message }) }
        setContentView(
            ScrollView(this).apply {
                setOnApplyWindowInsetsListener { view, insets ->
                    view.setPadding(
                        insets.systemWindowInsetLeft,
                        insets.systemWindowInsetTop,
                        insets.systemWindowInsetRight,
                        insets.systemWindowInsetBottom,
                    )
                    insets
                }
                addView(content, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
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
        menu.findItem(1)?.isVisible = authentication.server != null && settings == null
        return super.onPrepareOptionsMenu(menu)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean =
        when (item.itemId) {
            1 -> {
                showSettings()
                true
            }
            android.R.id.home -> {
                leaveSettings()
                true
            }
            else -> super.onOptionsItemSelected(item)
        }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (settings != null) leaveSettings() else super.onBackPressed()
    }

    private fun showSettings() {
        val server = authentication.server ?: return
        val screen =
            AtlasAIAccountsScreen(this, server, authentication::aiAccounts, ::openBrowser) {
                settings?.close()
                settings = null
                actionBar?.setDisplayHomeAsUpEnabled(false)
                authentication.signOut()
            }
        settings = screen
        actionBar?.setDisplayHomeAsUpEnabled(true)
        invalidateOptionsMenu()
        setContentView(screen.view)
        screen.load()
    }

    private fun leaveSettings() {
        if (settings?.back() == true) return
        settings?.close()
        settings = null
        actionBar?.setDisplayHomeAsUpEnabled(false)
        render()
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
