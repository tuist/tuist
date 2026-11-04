package dev.tuist.app.ui.notifications

import androidx.compose.foundation.layout.Box
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.R
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationPreference
import dev.tuist.app.data.push.PushRegistrationManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ProjectNotificationsViewModel @Inject constructor(
    private val notificationsRepository: NotificationsRepository,
    private val pushRegistrationManager: PushRegistrationManager,
) : ViewModel() {

    private val _accounts = MutableStateFlow<List<AccountNotificationPreference>>(emptyList())
    val accounts: StateFlow<List<AccountNotificationPreference>> = _accounts.asStateFlow()

    /** The bell is hidden until the user turns on notifications on this device. */
    private val _isDeviceEnabled = MutableStateFlow(false)
    val isDeviceEnabled: StateFlow<Boolean> = _isDeviceEnabled.asStateFlow()

    private val _isUpdating = MutableStateFlow(false)
    val isUpdating: StateFlow<Boolean> = _isUpdating.asStateFlow()

    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()

    private var loadJob: Job? = null

    /** Refreshes the preferences; the bell stays hidden while they're unavailable. */
    fun load() {
        _isDeviceEnabled.value = pushRegistrationManager.isDeviceEnabled
        if (_isUpdating.value) return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            try {
                _accounts.value = notificationsRepository.newPreviewPreferences()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Leave the previous preferences in place.
            }
        }
    }

    /**
     * Turns the project on or off. Matching the account clears the override, so the project follows it again.
     * Applies the change right away, then adopts the server's preferences, or reloads them if the change fails.
     */
    fun setEnabled(projectFullName: String, enabled: Boolean) {
        if (_isUpdating.value) return
        val (account, project) = _accounts.value.findProject(projectFullName) ?: return
        val setting = account.projectSetting(enabled)
        // A refresh still in flight would overwrite the change with stale preferences.
        loadJob?.cancel()
        _isUpdating.value = true
        _accounts.update { it.withProjectSetting(account.handle, project.handle, setting) }
        viewModelScope.launch {
            try {
                _accounts.value = notificationsRepository.updateNewPreviewProject(account.handle, project.handle, setting)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _accounts.value = try {
                    notificationsRepository.newPreviewPreferences()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    _accounts.value.withProjectSetting(account.handle, project.handle, project.setting)
                }
                _errorEvents.emit(e.message ?: "Failed to save the notification preference")
            } finally {
                _isUpdating.value = false
            }
        }
    }
}

/** Finds a project by its full handle (`account/project`). */
internal fun List<AccountNotificationPreference>.findProject(
    projectFullName: String,
): Pair<AccountNotificationPreference, ProjectNotificationPreference>? {
    val accountHandle = projectFullName.substringBefore('/')
    val projectHandle = projectFullName.substringAfter('/', missingDelimiterValue = "")
    val account = find { it.handle == accountHandle } ?: return null
    val project = account.projects.find { it.handle == projectHandle } ?: return null
    return account to project
}

/**
 * Top app bar action that turns new-preview notifications for one project on or off. It's hidden until the user turns
 * on notifications on this device, and when the project isn't in the user's accounts.
 */
@Composable
fun ProjectNotificationsBell(
    projectFullName: String,
    snackbarHostState: SnackbarHostState,
    viewModel: ProjectNotificationsViewModel = hiltViewModel(),
) {
    val accounts by viewModel.accounts.collectAsStateWithLifecycle()
    val isDeviceEnabled by viewModel.isDeviceEnabled.collectAsStateWithLifecycle()
    val isUpdating by viewModel.isUpdating.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }
    // Profile can change the same preferences and the opt-in, so reload whenever the screen resumes.
    LifecycleResumeEffect(projectFullName) {
        viewModel.load()
        onPauseOrDispose {}
    }

    if (!isDeviceEnabled) return
    val (_, project) = accounts.findProject(projectFullName) ?: return
    ProjectNotificationsMenu(
        isEnabled = project.enabled,
        isUpdating = isUpdating,
        onEnabledChange = { viewModel.setEnabled(projectFullName, it) },
    )
}

@Composable
internal fun ProjectNotificationsMenu(
    isEnabled: Boolean,
    isUpdating: Boolean,
    onEnabledChange: (Boolean) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            val description = stringResource(
                if (isEnabled) R.string.notifications_bell_on else R.string.notifications_bell_off,
            )
            if (isEnabled) {
                Icon(Icons.Filled.Notifications, contentDescription = description)
            } else {
                Icon(painterResource(R.drawable.ic_notifications_off), contentDescription = description)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.notifications_notify_new_previews)) },
                trailingIcon = { Checkbox(checked = isEnabled, onCheckedChange = null) },
                enabled = !isUpdating,
                onClick = {
                    expanded = false
                    onEnabledChange(!isEnabled)
                },
            )
        }
    }
}
