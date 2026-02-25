package dev.tuist.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _account = MutableStateFlow<Account?>(null)
    val account: StateFlow<Account?> = _account.asStateFlow()

    init {
        viewModelScope.launch {
            val state = authRepository.authState.first { it is AuthState.LoggedIn }
            _account.value = (state as AuthState.LoggedIn).account
        }
    }

    fun signOut() {
        authRepository.signOut()
    }
}
