package dev.tuist.app.ui.notifications

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.data.push.NotificationRule
import dev.tuist.app.data.push.NotificationsError
import dev.tuist.app.data.push.NotificationsRepository
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
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class NotificationsContentState(
    val isPushAvailable: Boolean,
    val isDeviceEnabled: Boolean,
    val currentInstallationId: String?,
    val rules: List<NotificationRule>,
    /** `account/project` handles the user can pick for a rule. */
    val projects: List<String>,
    val devices: List<PushDevice>,
    val isUpdatingDevice: Boolean = false,
    /** Rules with a change in flight, whose controls stay disabled until it finishes. */
    val rulesInFlight: Set<String> = emptySet(),
)

sealed interface NotificationsUiState {
    data object Loading : NotificationsUiState
    data class Success(val content: NotificationsContentState) : NotificationsUiState
    /** The server predates notification rules, or doesn't accept them from this sign-in. */
    data object Unsupported : NotificationsUiState
    data class Error(val message: String) : NotificationsUiState
}

@HiltViewModel
class NotificationsViewModel @Inject constructor(
    private val notificationsRepository: NotificationsRepository,
    private val pushRegistrationManager: PushRegistrationManager,
) : ViewModel() {

    private val _uiState = MutableStateFlow<NotificationsUiState>(NotificationsUiState.Loading)
    val uiState: StateFlow<NotificationsUiState> = _uiState.asStateFlow()

    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()

    /** Condition options per project, fetched once per screen. */
    private val conditionOptionsCache = mutableMapOf<String, Map<String, List<String>>>()

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

    /** Creates [rule] when it has no ID yet, otherwise updates it. Calls [onSaved] once the server saved it. */
    fun save(rule: NotificationRule, onSaved: () -> Unit = {}) {
        val id = rule.id
        if (id != null && id in currentContent()?.rulesInFlight.orEmpty()) return
        if (id != null) updateContent { it.copy(rulesInFlight = it.rulesInFlight + id) }
        viewModelScope.launch {
            try {
                if (id == null) {
                    val created = notificationsRepository.createRule(rule)
                    updateContent { it.copy(rules = it.rules + created) }
                } else {
                    val saved = notificationsRepository.updateRule(rule)
                    updateContent { content -> content.copy(rules = content.rules.map { if (it.id == id) saved else it }) }
                }
                onSaved()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorEvents.emit(e.message ?: "Failed to save the notification rule")
            } finally {
                if (id != null) updateContent { it.copy(rulesInFlight = it.rulesInFlight - id) }
            }
        }
    }

    fun setEnabled(rule: NotificationRule, enabled: Boolean) = save(rule.copy(isEnabled = enabled))

    fun delete(rule: NotificationRule, onDeleted: () -> Unit = {}) {
        val id = rule.id ?: return
        updateContent { it.copy(rulesInFlight = it.rulesInFlight + id) }
        viewModelScope.launch {
            try {
                notificationsRepository.deleteRule(id)
                updateContent { content -> content.copy(rules = content.rules.filterNot { it.id == id }) }
                onDeleted()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _errorEvents.emit(e.message ?: "Failed to delete the notification rule")
            } finally {
                updateContent { it.copy(rulesInFlight = it.rulesInFlight - id) }
            }
        }
    }

    /**
     * The values the user can pick for [condition] (`track` or `git_branch`) in [rule]'s projects, sorted. A rule for
     * any project has no suggestions, since it would mean asking every project.
     */
    suspend fun options(condition: String, rule: NotificationRule): List<String> {
        val values = sortedSetOf<String>()
        for (project in rule.projects) {
            val options = conditionOptionsCache[project] ?: try {
                notificationsRepository.conditionOptions(rule.event, project)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }?.also { conditionOptionsCache[project] = it }
            values += options?.get(condition).orEmpty()
        }
        return values.toList()
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

    private fun currentContent(): NotificationsContentState? =
        (_uiState.value as? NotificationsUiState.Success)?.content

    private suspend fun fetchContent(): NotificationsContentState = coroutineScope {
        val rules = async { notificationsRepository.listRules() }
        val devices = async { notificationsRepository.listDevices() }
        val projects = async { notificationsRepository.listProjects() }
        val installationId = pushRegistrationManager.installationId
        NotificationsContentState(
            isPushAvailable = pushRegistrationManager.isAvailable,
            isDeviceEnabled = pushRegistrationManager.isDeviceEnabled,
            currentInstallationId = installationId,
            rules = rules.await(),
            projects = projects.await(),
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

internal val NotificationRule.projectsText: String
    get() = when (projects.size) {
        0 -> "Any project"
        1 -> projects.first()
        else -> "${projects.size} projects"
    }

/** The rule as a sentence, like an automation's name. */
internal val NotificationRule.title: String
    get() = buildString {
        append("When a preview of $projectsText is published")
        track?.let { append(" on ${it.phrase("track")}") }
        gitBranch?.let { append(" from ${it.phrase("branch")}") }
        if (publishedByMe) append(" by me")
    }

private fun dev.tuist.app.data.push.ValueMatch.phrase(noun: String): String = when (this) {
    is dev.tuist.app.data.push.ValueMatch.Is -> "‘$value’"
    is dev.tuist.app.data.push.ValueMatch.Contains -> "a $noun containing ‘$value’"
}
