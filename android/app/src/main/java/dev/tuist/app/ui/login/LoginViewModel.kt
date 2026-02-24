package dev.tuist.app.ui.login

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthEvent
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.AuthRepository
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val authEventBus: AuthEventBus,
) : ViewModel() {

    private val _messages = Channel<String>(Channel.BUFFERED)
    val messages = _messages.receiveAsFlow()

    init {
        viewModelScope.launch {
            authEventBus.events.collect { event ->
                when (event) {
                    is AuthEvent.SessionExpired ->
                        _messages.send("Your session expired. Please sign in again.")
                }
            }
        }
    }

    fun signIn(activity: Activity) {
        authRepository.startOAuthFlow(activity, "/oauth2/authorize")
    }

    fun signInWithApple(activity: Activity) {
        authRepository.startOAuthFlow(activity, "/oauth2/apple")
    }

    fun signInWithGoogle(activity: Activity) {
        authRepository.startOAuthFlow(activity, "/oauth2/google")
    }

    fun signInWithGitHub(activity: Activity) {
        authRepository.startOAuthFlow(activity, "/oauth2/github")
    }
}
