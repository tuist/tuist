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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val authState = authRepository.authState.stateIn(
            scope = lifecycleScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = AuthState.LoggedOut,
        )

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
