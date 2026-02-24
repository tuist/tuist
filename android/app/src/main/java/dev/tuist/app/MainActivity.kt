package dev.tuist.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import dagger.hilt.android.AndroidEntryPoint
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.TuistEnvironment
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.navigation.TuistNavGraph
import dev.tuist.app.ui.theme.TuistTheme
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var environmentConfig: EnvironmentConfig

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (handleEnvironmentSwitch(intent)) return

        val authState = authRepository.authState.stateIn(
            scope = lifecycleScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = AuthState.LoggedOut,
        )

        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Environment: ${environmentConfig.current.name} (${environmentConfig.serverUrl})")
        }

        intent?.data?.let { uri ->
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "onCreate intent data: $uri")
            }
            handleDeepLink(uri)
        }

        setContent {
            TuistTheme {
                TuistNavGraph(authState = authState)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "onNewIntent data: ${intent.data}")
        }
        intent.data?.let { uri -> handleDeepLink(uri) }
    }

    private fun handleEnvironmentSwitch(intent: Intent?): Boolean {
        if (!BuildConfig.DEBUG) return false
        val envName = intent?.getStringExtra("environment") ?: return false
        val env = TuistEnvironment.fromName(envName)
        if (env == null) {
            Log.w(TAG, "Unknown environment: $envName. Valid: ${TuistEnvironment.entries.joinToString { it.name.lowercase() }}")
            return false
        }
        if (environmentConfig.setEnvironment(env)) {
            Log.i(TAG, "Switching to ${env.name} (${env.serverUrl}), restarting...")
            authRepository.signOut()
            val restartIntent = packageManager.getLaunchIntentForPackage(packageName)!!
            restartIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            startActivity(restartIntent)
            Runtime.getRuntime().exit(0)
            return true
        }
        Log.d(TAG, "Already on ${env.name}")
        return false
    }

    private fun handleDeepLink(uri: Uri) {
        val isOAuthCallback = when {
            uri.scheme == "tuist" && uri.host == "oauth-callback" -> true
            uri.path?.startsWith("/oauth/callback/android") == true -> true
            else -> false
        }
        if (isOAuthCallback) {
            lifecycleScope.launch { authRepository.handleOAuthCallback(uri) }
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
