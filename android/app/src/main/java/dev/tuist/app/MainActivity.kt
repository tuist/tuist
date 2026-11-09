package dev.tuist.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.viewModels
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import dagger.hilt.android.AndroidEntryPoint
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.TuistEnvironment
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.navigation.TuistNavGraph
import dev.tuist.app.navigation.AppNavigationViewModel
import dev.tuist.app.navigation.openWebTab
import dev.tuist.app.ui.theme.TuistTheme
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    private val navigation: AppNavigationViewModel by viewModels()

    @Inject
    lateinit var authRepository: AuthRepository

    @Inject
    lateinit var environmentConfig: EnvironmentConfig

    @Inject
    lateinit var featureFlags: FeatureFlagsRepository

    @Inject
    lateinit var pushRegistrationManager: PushRegistrationManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (handleEnvironmentSwitch(intent)) return

        val authState: StateFlow<AuthState?> = authRepository.authState.stateIn(
            scope = lifecycleScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = null,
        )

        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Environment: ${environmentConfig.current.name} (${environmentConfig.serverUrl})")
        }

        // Refreshes the flags on launch, whenever the session changes, and when the app returns to the foreground.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(authRepository.authState, authRepository.session) { state, session -> state to session }
                    .distinctUntilChanged().collectLatest { (state, session) ->
                        featureFlags.refresh(state, session)
                    }
            }
        }

        if (savedInstanceState == null) intent?.data?.let { uri ->
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "onCreate intent data: $uri")
            }
            handleDeepLink(uri)
        }

        // Push ownership cleanup runs independently of the activity lifecycle in the manager.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                authRepository.authState.distinctUntilChanged().collect { state ->
                    when (state) {
                        is AuthState.LoggedIn -> pushRegistrationManager.requestSync()
                        AuthState.LoggedOut -> Unit
                        AuthState.Authenticating -> Unit
                    }
                }
            }
        }

        setContent {
            TuistTheme {
                TuistNavGraph(authState = authState, navigation = navigation)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "onNewIntent data: ${intent.data}")
        }
        if (handleEnvironmentSwitch(intent)) return
        intent.data?.let { uri -> handleDeepLink(uri) }
    }

    private fun handleEnvironmentSwitch(intent: Intent?): Boolean {
        if (!BuildConfig.DEBUG || intent?.data != null) return false
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
            uri.scheme == "https" && uri.path == "/oauth/callback/android" -> true
            else -> false
        }
        if (isOAuthCallback) {
            lifecycleScope.launch {
                if (authRepository.handleOAuthCallback(uri).isFailure) {
                    Toast.makeText(this@MainActivity, R.string.profiles_login_failed, Toast.LENGTH_LONG).show()
                }
            }
        } else if (!navigation.openUrl(uri.toString())) {
            val isWebUrl = navigation.isCurrentServerWebUrl(uri.toString())
            if (isWebUrl && openWebTab(uri.toString())) return
            val message = if (isWebUrl) R.string.navigation_browser_unavailable else R.string.navigation_link_error
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
