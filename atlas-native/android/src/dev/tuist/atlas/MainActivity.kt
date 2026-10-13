package dev.tuist.atlas

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.InputType
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {
    private lateinit var authentication: AtlasAuthentication

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = getString(R.string.app_name)
        authentication = (lastNonConfigurationInstance as? AtlasAuthentication) ?: AtlasAuthentication(this)
        if (savedInstanceState == null && intent.data == null) authentication.restore()
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

    override fun onDestroy() {
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
        if (server == null) {
            button("Sign in to Atlas") { authentication.signIn("https://atlas.tuist.dev", false) }
            button("Self-hosted server") { selfHostedPrompt() }
            button("Restore saved session") { authentication.restore() }
        } else {
            content.addView(TextView(this).apply { text = Uri.parse(server).host })
            AtlasCore().sections().forEach { section ->
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
            button("Sign out") { authentication.signOut() }
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
