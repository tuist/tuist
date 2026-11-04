package dev.tuist.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsError
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationSetting
import dev.tuist.app.data.push.PushDevice
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.data.push.PushRegistrationResult
import kotlinx.coroutines.CancellationException
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
    /** Accounts and projects with a change in flight, whose switches stay disabled until it finishes. */
    val changesInFlight: Set<String> = emptySet(),
) {
    /** Accounts without projects have nothing to choose, so they aren't shown. */
    val accountsWithProjects: List<AccountNotificationPreference> get() = accounts.filter { it.projects.isNotEmpty() }
}

sealed interface NotificationsUiState {
    data object Loading : NotificationsUiState
    data class Success(val content: NotificationsContentState) : NotificationsUiState
    /** The server predates notifications, or doesn't accept them from this sign-in. */
    data object Unsupported : NotificationsUiState
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

    /**
     * Set when changes overlap or one fails, so the last one to finish reloads instead of adopting a response that
     * may not include the others.
     */
    private var needsReload = false

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            _uiState.value = NotificationsUiState.Loading
            _uiState.value = try {
                NotificationsUiState.Success(fetchContent())
            } catch (e: CancellationException) {
                throw e
            } catch (e: NotificationsError) {
                if (e.isUnsupported) NotificationsUiState.Unsupported else NotificationsUiState.Error(e.message.orEmpty())
            } catch (e: Exception) {
                NotificationsUiState.Error(e.message ?: "Failed to load notification settings")
            }
        }
    }

    /** The permission is only requested when the user turns notifications on, so granting it opts in. */
    fun onPermissionGranted() = setDeviceEnabled(true)

    fun setDeviceEnabled(enabled: Boolean) {
        if (currentContent()?.isUpdatingDevice != false) return
        updateContent { it.copy(isDeviceEnabled = enabled, isUpdatingDevice = true) }
        viewModelScope.launch {
            val result = pushRegistrationManager.setDeviceEnabled(enabled)
            updateContent { it.copy(isDeviceEnabled = pushRegistrationManager.isDeviceEnabled, isUpdatingDevice = false) }
            if (result is PushRegistrationResult.Failed) _errorEvents.emit(result.message)
            refreshDevices()
        }
    }

    /** Changes the account's choice, which every project without its own override follows. */
    fun setAccountEnabled(accountHandle: String, enabled: Boolean) {
        update(
            key = accountHandle,
            change = { it.withAccountEnabled(accountHandle, enabled) },
        ) { notificationsRepository.updateNewPreviewAccount(accountHandle, enabled) }
    }

    /** Turns a project on or off. Matching the account clears the project's override, so it follows the account again. */
    fun setProjectEnabled(accountHandle: String, projectHandle: String, enabled: Boolean) {
        val account = currentContent()?.accounts?.find { it.handle == accountHandle } ?: return
        val setting = account.projectSetting(enabled)
        update(
            key = "$accountHandle/$projectHandle",
            change = { it.withProjectSetting(accountHandle, projectHandle, setting) },
        ) { notificationsRepository.updateNewPreviewProject(accountHandle, projectHandle, setting) }
    }

    fun removeDevice(device: PushDevice) {
        updateContent { content ->
            content.copy(devices = content.devices.filterNot { it.registrationId == device.registrationId })
        }
        viewModelScope.launch {
            try {
                notificationsRepository.removeDevice(device.registrationId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorEvents.emit(e.message ?: "Failed to remove the device")
                refreshDevices()
            }
        }
    }

    /**
     * Applies the change right away and sends it. A change adopts the server's response only when no other change
     * overlapped it; otherwise the last one to finish reloads, so a late response can't undo a newer change. A failed
     * change also reloads rather than restoring a snapshot.
     */
    private fun update(
        key: String,
        change: (List<AccountNotificationPreference>) -> List<AccountNotificationPreference>,
        send: suspend () -> List<AccountNotificationPreference>,
    ) {
        val content = currentContent() ?: return
        if (key in content.changesInFlight) return
        if (content.changesInFlight.isNotEmpty()) needsReload = true
        val previous = content.accounts
        updateContent { it.copy(accounts = change(it.accounts), changesInFlight = it.changesInFlight + key) }
        viewModelScope.launch {
            var saved: List<AccountNotificationPreference>? = null
            var failure: Exception? = null
            try {
                saved = send()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e
                needsReload = true
            }
            var accounts: List<AccountNotificationPreference>? = null
            if (currentContent()?.changesInFlight == setOf(key)) {
                if (needsReload) {
                    needsReload = false
                    accounts = reloadPreferences() ?: saved ?: previous
                } else {
                    accounts = saved
                }
            }
            updateContent { it.copy(accounts = accounts ?: it.accounts, changesInFlight = it.changesInFlight - key) }
            failure?.let { _errorEvents.emit(it.message ?: "Failed to save the notification preference") }
        }
    }

    private suspend fun reloadPreferences(): List<AccountNotificationPreference>? = try {
        notificationsRepository.newPreviewPreferences()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    private fun currentContent(): NotificationsContentState? =
        (_uiState.value as? NotificationsUiState.Success)?.content

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
        } catch (e: CancellationException) {
            throw e
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

/** The setting that makes a project [enabled]: following the account when it agrees, an override otherwise. */
internal fun AccountNotificationPreference.projectSetting(enabled: Boolean): ProjectNotificationSetting = when {
    enabled == this.enabled -> ProjectNotificationSetting.Default
    enabled -> ProjectNotificationSetting.On
    else -> ProjectNotificationSetting.Off
}

internal enum class AccountNotificationSummary { On, Off, Custom }

/** On or Off when every project agrees, Custom otherwise. */
internal val AccountNotificationPreference.summary: AccountNotificationSummary
    get() = when {
        projects.all { it.enabled } -> AccountNotificationSummary.On
        projects.none { it.enabled } -> AccountNotificationSummary.Off
        else -> AccountNotificationSummary.Custom
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
