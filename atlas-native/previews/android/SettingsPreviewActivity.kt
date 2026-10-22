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
import org.json.JSONObject

class SettingsPreviewActivity : Activity() {
    private lateinit var screen: AtlasAIAccountsScreen
    private lateinit var accounts: AtlasAIAccountsModel
    private var unregisterBack: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra("model-checks", false)) checkAccountModel(applicationContext)
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
