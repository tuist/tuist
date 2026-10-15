package dev.tuist.atlas.preview

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import dev.tuist.atlas.AtlasAIAccountsScreen
import org.json.JSONObject

class SettingsPreviewActivity : Activity() {
    private lateinit var screen: AtlasAIAccountsScreen

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val main = Handler(Looper.getMainLooper())
        screen =
            AtlasAIAccountsScreen(
                this,
                "https://atlas.example.org",
                { request, complete ->
                    val response =
                        when (request.getString("action")) {
                            "list" ->
                                """{"providers":[
                                {"provider":"claude","credential_configured":false,"login_available":true},
                                {"provider":"chatgpt","credential_configured":false,"login_available":true}]}
                                """
                            "start_chatgpt" ->
                                """{"login_id":"preview-only","user_code":"DEMO-CODE",
                                "verification_url":"https://auth.openai.com/codex/device",
                                "interval":5,"expires_at":"2030-01-01T00:00:00Z"}
                                """
                            "cancel_chatgpt" -> """{"status":"cancelled"}"""
                            else -> """{"status":"pending"}"""
                        }
                    main.post { complete(Result.success(JSONObject(response))) }
                },
                { uri -> startActivity(Intent(Intent.ACTION_VIEW, uri)) },
                {},
            )
        setContentView(screen.view)
        screen.load()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!screen.back()) super.onBackPressed()
    }

    override fun onDestroy() {
        screen.close()
        super.onDestroy()
    }
}
