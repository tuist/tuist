package dev.tuist.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationSetting
import dev.tuist.app.data.push.PushDevice
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.data.push.PushRegistrationResult
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationsContentState(
    val isPushAvailable: Boolean,
    val isDeviceEnabled: Boolean,
    val currentInstallationId: String?,
    val accounts: List<AccountNotificationPreference>,
    /** The signed-in user's handle, which identifies their personal account. */
    val personalAccountHandle: String?,
    val devices: List<PushDevice>,
    val isUpdatingDevice: Boolean = false,
)

sealed interface NotificationsUiState {
    data object Loading : NotificationsUiState
    data class Success(val content: NotificationsContentState) : NotificationsUiState
    data class Error(val message: String) : NotificationsUiState
}

@HiltViewModel
class NotificationsViewModel @Inject constructor(
    private val notificationsRepository: NotificationsRepository,
    private val pushRegistrationManager: PushRegistrationManager,
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<NotificationsUiState>(NotificationsUiState.Loading)
    val uiState: StateFlow<NotificationsUiState> = _uiState.asStateFlow()

    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = NotificationsUiState.Loading
            try {
                _uiState.value = NotificationsUiState.Success(fetchContent())
            } catch (e: Exception) {
                _uiState.value = NotificationsUiState.Error(e.message ?: "Failed to load notification settings")
            }
        }
    }

    fun onPermissionGranted() {
        viewModelScope.launch {
            pushRegistrationManager.sync(force = true)
            refreshDevices()
        }
    }

    fun setDeviceEnabled(enabled: Boolean) {
        updateContent { it.copy(isDeviceEnabled = enabled, isUpdatingDevice = true) }
        viewModelScope.launch {
            val result = pushRegistrationManager.setDeviceEnabled(enabled)
            updateContent { it.copy(isDeviceEnabled = pushRegistrationManager.isDeviceEnabled, isUpdatingDevice = false) }
            if (result is PushRegistrationResult.Failed) _errorEvents.emit(result.message)
            refreshDevices()
        }
    }

    fun setAccountEnabled(accountHandle: String, enabled: Boolean) {
        val previous = currentAccounts()?.find { it.handle == accountHandle }?.enabled ?: return
        savePreference(
            apply = { it.withAccountEnabled(accountHandle, enabled) },
            rollback = { it.withAccountEnabled(accountHandle, previous) },
        ) { notificationsRepository.updateNewPreviewAccount(accountHandle, enabled) }
    }

    fun setProjectSetting(accountHandle: String, projectHandle: String, setting: ProjectNotificationSetting) {
        val previous = currentAccounts()?.find { it.handle == accountHandle }
            ?.projects?.find { it.handle == projectHandle }?.setting ?: return
        savePreference(
            apply = { it.withProjectSetting(accountHandle, projectHandle, setting) },
            rollback = { it.withProjectSetting(accountHandle, projectHandle, previous) },
        ) { notificationsRepository.updateNewPreviewProject(accountHandle, projectHandle, setting) }
    }

    fun removeDevice(device: PushDevice) {
        viewModelScope.launch {
            try {
                notificationsRepository.removeDevice(device.registrationId)
                updateContent { content ->
                    content.copy(devices = content.devices.filterNot { it.registrationId == device.registrationId })
                }
            } catch (e: Exception) {
                _errorEvents.emit(e.message ?: "Failed to remove the device")
            }
        }
    }

    private fun currentAccounts(): List<AccountNotificationPreference>? =
        (_uiState.value as? NotificationsUiState.Success)?.content?.accounts

    /**
     * Shows the change immediately and replaces the state with the server's preferences once saved. On failure only
     * the changed value is reverted, so a concurrent change to another account or project is kept.
     */
    private fun savePreference(
        apply: (List<AccountNotificationPreference>) -> List<AccountNotificationPreference>,
        rollback: (List<AccountNotificationPreference>) -> List<AccountNotificationPreference>,
        save: suspend () -> List<AccountNotificationPreference>,
    ) {
        updateContent { it.copy(accounts = apply(it.accounts)) }
        viewModelScope.launch {
            try {
                val saved = save()
                updateContent { it.copy(accounts = saved) }
            } catch (e: Exception) {
                updateContent { it.copy(accounts = rollback(it.accounts)) }
                _errorEvents.emit(e.message ?: "Failed to save the notification preference")
            }
        }
    }

    private suspend fun fetchContent(): NotificationsContentState = coroutineScope {
        val accounts = async { notificationsRepository.newPreviewPreferences() }
        val devices = async { notificationsRepository.listDevices() }
        val installationId = pushRegistrationManager.installationId
        NotificationsContentState(
            isPushAvailable = pushRegistrationManager.isAvailable,
            isDeviceEnabled = pushRegistrationManager.isDeviceEnabled,
            currentInstallationId = installationId,
            accounts = accounts.await(),
            personalAccountHandle = (authRepository.authState.first() as? AuthState.LoggedIn)?.account?.handle,
            devices = sortDevices(devices.await(), installationId),
        )
    }

    private suspend fun refreshDevices() {
        try {
            val devices = notificationsRepository.listDevices()
            val installationId = pushRegistrationManager.installationId
            updateContent {
                it.copy(currentInstallationId = installationId, devices = sortDevices(devices, installationId))
            }
        } catch (e: Exception) {
            _errorEvents.emit(e.message ?: "Failed to load devices")
        }
    }

    private fun updateContent(change: (NotificationsContentState) -> NotificationsContentState) {
        _uiState.update { state ->
            if (state is NotificationsUiState.Success) state.copy(content = change(state.content)) else state
        }
    }

    private fun sortDevices(devices: List<PushDevice>, installationId: String?): List<PushDevice> =
        devices.sortedWith(
            compareByDescending<PushDevice> { it.installationId == installationId }
                .thenByDescending { it.lastSeenAt },
        )
}

internal fun List<AccountNotificationPreference>.withAccountEnabled(
    accountHandle: String,
    enabled: Boolean,
): List<AccountNotificationPreference> = map { account ->
    if (account.handle != accountHandle) return@map account
    account.copy(
        enabled = enabled,
        projects = account.projects.map { project ->
            if (project.setting == ProjectNotificationSetting.Default) project.copy(enabled = enabled) else project
        },
    )
}

internal fun List<AccountNotificationPreference>.withProjectSetting(
    accountHandle: String,
    projectHandle: String,
    setting: ProjectNotificationSetting,
): List<AccountNotificationPreference> = map { account ->
    if (account.handle != accountHandle) return@map account
    account.copy(
        projects = account.projects.map { project ->
            if (project.handle != projectHandle) return@map project
            project.copy(
                setting = setting,
                enabled = when (setting) {
                    ProjectNotificationSetting.Default -> account.enabled
                    ProjectNotificationSetting.On -> true
                    ProjectNotificationSetting.Off -> false
                },
            )
        },
    )
}
