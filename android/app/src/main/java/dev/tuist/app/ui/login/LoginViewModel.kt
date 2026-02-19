package dev.tuist.app.ui.login

import android.app.Activity
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import javax.inject.Inject

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

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
