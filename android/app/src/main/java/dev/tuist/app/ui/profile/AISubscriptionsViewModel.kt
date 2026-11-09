package dev.tuist.app.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.api.model.AISubscription1
import dev.tuist.app.api.model.ChatGPTSubscriptionLogin1
import dev.tuist.app.data.aisubscriptions.AISubscriptionsRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.OffsetDateTime
import javax.inject.Inject

data class AISubscriptionsUiState(
    val subscriptions: List<AISubscription1> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val isConnectingClaude: Boolean = false,
    val isSavingClaude: Boolean = false,
    val claudeError: String? = null,
    val chatGPTLogin: ChatGPTSubscriptionLogin1? = null,
    val chatGPTError: String? = null,
    val isChatGPTLoginExpired: Boolean = false,
)

@HiltViewModel
class AISubscriptionsViewModel @Inject constructor(
    private val repository: AISubscriptionsRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(AISubscriptionsUiState())
    val state: StateFlow<AISubscriptionsUiState> = _state.asStateFlow()

    private var polling: Job? = null

    init {
        load()
    }

    fun load() = perform { repository.list() }

    fun disconnect(provider: String) = perform { repository.disconnect(provider) }

    fun connect(subscription: AISubscription1) {
        when (subscription.provider) {
            AISubscriptionsRepository.CLAUDE -> _state.update { it.copy(isConnectingClaude = true, claudeError = null) }
            AISubscriptionsRepository.CHATGPT -> startChatGPTLogin()
        }
    }

    private fun startChatGPTLogin() {
        viewModelScope.launch {
            try {
                val login = repository.startChatGPTLogin()
                _state.update { it.copy(chatGPTLogin = login, chatGPTError = null, isChatGPTLoginExpired = false) }
                poll(login)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message) }
            }
        }
    }

    fun saveClaudeToken(token: String) {
        _state.update { it.copy(isSavingClaude = true, claudeError = null) }
        viewModelScope.launch {
            try {
                val subscriptions = repository.connectClaude(token.trim())
                _state.update { it.copy(subscriptions = subscriptions, isConnectingClaude = false, isSavingClaude = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(isSavingClaude = false, claudeError = e.message) }
            }
        }
    }

    fun dismissClaude() = _state.update { it.copy(isConnectingClaude = false, claudeError = null) }

    fun dismissChatGPT() {
        val login = _state.value.chatGPTLogin ?: return
        val ended = _state.value.chatGPTError != null || _state.value.isChatGPTLoginExpired
        polling?.cancel()
        _state.update { it.copy(chatGPTLogin = null, chatGPTError = null, isChatGPTLoginExpired = false) }
        viewModelScope.launch {
            if (!ended) runCatching { repository.cancelChatGPTLogin(login.loginId) }
            load()
        }
    }

    fun dismissError() = _state.update { it.copy(error = null) }

    private fun poll(login: ChatGPTSubscriptionLogin1) {
        polling?.cancel()
        polling = viewModelScope.launch {
            while (OffsetDateTime.now().isBefore(login.expiresAt)) {
                delay(login.interval.coerceAtLeast(1) * 1000L)
                try {
                    if (repository.pollChatGPTLogin(login.loginId)) {
                        _state.update { it.copy(chatGPTLogin = null) }
                        load()
                        return@launch
                    }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    _state.update { it.copy(chatGPTError = e.message) }
                    return@launch
                }
            }
            _state.update { it.copy(isChatGPTLoginExpired = true) }
        }
    }

    private fun perform(action: suspend () -> List<AISubscription1>) {
        viewModelScope.launch {
            try {
                val subscriptions = action()
                _state.update { it.copy(subscriptions = subscriptions, isLoading = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }
}
