package dev.tuist.atlas.preview

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import dev.tuist.atlas.AtlasAIAccountsModel
import dev.tuist.atlas.AtlasAIAccountsScreen
import dev.tuist.atlas.AtlasConnectionsModel
import org.json.JSONObject

class SettingsPreviewActivity : Activity() {
    private lateinit var screen: AtlasAIAccountsScreen
    private lateinit var accounts: AtlasAIAccountsModel
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("model-checks", false)) {
            checkAccountModel(applicationContext)
            checkConnections()
        }
        accounts = (lastNonConfigurationInstance as? AtlasAIAccountsModel) ?: fixture(savedInstanceState?.getString("login_id"))
        screen =
            AtlasAIAccountsScreen(
                this,
                "https://atlas.example.org",
                accounts,
                { uri -> startActivity(Intent(Intent.ACTION_VIEW, uri)) },
                { if (!screen.back()) finish() },
                signOut = {},
            )
        val connections =
            AtlasConnectionsModel { action, completion ->
                val response =
                    if (action.getString("action") == "list") {
                        Result.success(
                            JSONObject(
                                """{"connections":[
                    {"provider":"github","name":"GitHub","configured":true,"account_name":null,"status":"not_connected"},
                    {"provider":"slack","name":"Slack","configured":true,"account_name":"Demo teammate · Demo workspace","status":"connected"},
                    {"provider":"google","name":"Google","configured":true,"account_name":"demo@example.org","status":"needs_authorization"}]}""",
                            ),
                        )
                    } else {
                        Result.failure(IllegalStateException("Preview only. No accounts are changed."))
                    }
                Handler(Looper.getMainLooper()).post { completion(response) }
            }
        connections.showing = intent.getBooleanExtra("connections", false)
        screen.connections(connections)
        connections.load()
        setContentView(screen.view)
        if (Build.VERSION.SDK_INT >= 33) {
            val callback = OnBackInvokedCallback { if (!screen.back()) finish() }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
            unregisterBack = { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(callback) }
        }
        screen.load()
    }

    override fun onRetainNonConfigurationInstance(): Any = accounts

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("login_id", accounts.pendingLoginId)
        super.onSaveInstanceState(outState)
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!screen.back()) super.onBackPressed()
    }

    override fun onDestroy() {
        screen.close(cancelPending = !isChangingConfigurations)
        unregisterBack?.invoke()
        super.onDestroy()
    }
}

private fun fixture(recoveredLoginId: String?): AtlasAIAccountsModel {
    val main = Handler(Looper.getMainLooper())
    return AtlasAIAccountsModel(recoveredLoginId) { request, complete ->
        val response =
            when (request.getString("action")) {
                "list" ->
                    """{"providers":[
                {"provider":"claude","credential_configured":false,"login_available":true},
                {"provider":"chatgpt","credential_configured":false,"login_available":true}]}"""
                "start_chatgpt" ->
                    """{"login_id":"preview-only","user_code":"DEMO-CODE",
                "verification_url":"https://auth.openai.com/codex/device","interval":5,"expires_at":"2030-01-01T00:00:00Z"}"""
                "cancel_chatgpt" -> """{"status":"cancelled"}"""
                else -> """{"status":"pending"}"""
            }
        main.post { complete(Result.success(JSONObject(response))) }
    }
}

private fun checkConnections() {
    val replies = mutableListOf<(Result<JSONObject>) -> Unit>()
    val model = AtlasConnectionsModel { _, completion -> replies.add(completion) }
    model.connect("github")
    replies.removeAt(
        0,
    )(Result.success(JSONObject().put("authorization_url", "https://atlas.example.org/connections/github/authorize?native=demo")))
    check(model.waiting && !model.busy)
    model.callback("preview-only") { valid -> check(!valid) }
    replies.removeAt(0)(Result.failure(IllegalStateException("Invalid return")))
    check(model.waiting && model.message == "Invalid return")
    model.cancel()
    replies.removeAt(0)(Result.success(JSONObject()))
    check(!model.waiting && model.authorizationURL == null)

    // A newly created model can receive a return restored by the auth coordinator.
    model.callback("preview-only") { valid -> check(valid) }
    replies.removeAt(0)(Result.success(JSONObject().put("provider", "github").put("status", "connected")))
    replies.removeAt(0)(Result.success(JSONObject("""{"connections":[{"provider":"github","status":"not_connected"}]}""")))
    check(model.showing && !model.waiting && model.connections.single().getString("status") == "not_connected")

    model.callback("preview-only") { error("A previous user's return must be ignored") }
    model.clear()
    replies.removeAt(0)(Result.success(JSONObject().put("provider", "github").put("status", "connected")))
    check(model.connections.isEmpty() && !model.busy && !model.waiting)
}
