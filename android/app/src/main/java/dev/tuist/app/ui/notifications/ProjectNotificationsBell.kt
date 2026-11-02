package dev.tuist.app.ui.notifications

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.tuist.app.R
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationPreference
import dev.tuist.app.data.push.ProjectNotificationSetting
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
) : ViewModel() {

    private val _accounts = MutableStateFlow<List<AccountNotificationPreference>>(emptyList())
    val accounts: StateFlow<List<AccountNotificationPreference>> = _accounts.asStateFlow()

    private val _errorEvents = MutableSharedFlow<String>()
    val errorEvents: SharedFlow<String> = _errorEvents.asSharedFlow()

    private var loadJob: Job? = null

    /** Refreshes the preferences; the bell stays hidden while they're unavailable. */
    fun load() {
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

    fun setSetting(projectFullName: String, setting: ProjectNotificationSetting) {
        val (account, project) = _accounts.value.findProject(projectFullName) ?: return
        val previous = project.setting
        // A refresh still in flight would overwrite the change with stale preferences.
        loadJob?.cancel()
        _accounts.update { it.withProjectSetting(account.handle, project.handle, setting) }
        viewModelScope.launch {
            try {
                _accounts.value = notificationsRepository.updateNewPreviewProject(account.handle, project.handle, setting)
            } catch (e: Exception) {
                _accounts.update { it.withProjectSetting(account.handle, project.handle, previous) }
                _errorEvents.emit(e.message ?: "Failed to save the notification preference")
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

/** Top app bar action to change new-preview notifications for one project; hidden when the project isn't known. */
@Composable
fun ProjectNotificationsBell(
    projectFullName: String,
    snackbarHostState: SnackbarHostState,
    viewModel: ProjectNotificationsViewModel = hiltViewModel(),
) {
    val accounts by viewModel.accounts.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }
    LaunchedEffect(projectFullName) { viewModel.load() }

    val (account, project) = accounts.findProject(projectFullName) ?: return
    ProjectNotificationsMenu(
        accountHandle = account.handle,
        accountEnabled = account.enabled,
        project = project,
        onSettingChange = { viewModel.setSetting(projectFullName, it) },
    )
}

@Composable
internal fun ProjectNotificationsMenu(
    accountHandle: String,
    accountEnabled: Boolean,
    project: ProjectNotificationPreference,
    onSettingChange: (ProjectNotificationSetting) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Box {
        IconButton(onClick = { expanded = true }) {
            val description = stringResource(
                if (project.enabled) R.string.notifications_bell_on else R.string.notifications_bell_off,
            )
            if (project.enabled) {
                Icon(Icons.Filled.Notifications, contentDescription = description)
            } else {
                Icon(painterResource(R.drawable.ic_notifications_off), contentDescription = description)
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            ProjectNotificationSetting.entries.forEach { setting ->
                DropdownMenuItem(
                    text = {
                        val (title, supporting) = when (setting) {
                            ProjectNotificationSetting.Default -> stringResource(R.string.notifications_follow_account, accountHandle) to
                                stringResource(
                                    if (accountEnabled) R.string.notifications_follow_on else R.string.notifications_follow_off,
                                )
                            ProjectNotificationSetting.On -> stringResource(R.string.notifications_always) to
                                stringResource(R.string.notifications_always_description)
                            ProjectNotificationSetting.Off -> stringResource(R.string.notifications_never) to
                                stringResource(R.string.notifications_never_description)
                        }
                        Column {
                            Text(title, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                text = supporting,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    trailingIcon = {
                        if (setting == project.setting) Icon(Icons.Filled.Check, contentDescription = null)
                    },
                    onClick = {
                        expanded = false
                        if (setting != project.setting) onSettingChange(setting)
                    },
                )
            }
        }
    }
}
