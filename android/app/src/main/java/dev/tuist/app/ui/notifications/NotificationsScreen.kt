package dev.tuist.app.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.InputChipDefaults
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.tuist.app.R
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.ProjectNotificationPreference
import dev.tuist.app.data.push.ProjectNotificationSetting
import dev.tuist.app.data.push.PushDevice
import dev.tuist.app.ui.noora.NooraSpacing
import java.time.Duration
import java.time.OffsetDateTime

@Composable
fun NotificationsScreen(
    onBack: () -> Unit,
    viewModel: NotificationsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val permission = rememberNotificationPermissionState(onGranted = viewModel::onPermissionGranted)
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }

    NotificationsScaffold(
        title = stringResource(R.string.notifications_title),
        onBack = onBack,
        snackbarHostState = snackbarHostState,
    ) {
        NotificationsStateContent(uiState, onRetry = viewModel::load) { content ->
            NotificationsContent(
                state = content,
                permissionStatus = permission.status,
                onRequestPermission = permission.request,
                onOpenSettings = permission.openSettings,
                onDeviceEnabledChange = { enabled ->
                    // Turning notifications on asks for the permission first; granting it opts in.
                    if (enabled && permission.status == NotificationPermissionStatus.NotGranted) {
                        permission.request()
                    } else {
                        viewModel.setDeviceEnabled(enabled)
                    }
                },
                onAccountEnabledChange = viewModel::setAccountEnabled,
                onResetProject = { account, project ->
                    viewModel.setProjectSetting(account, project, ProjectNotificationSetting.Default)
                },
                onRemoveDevice = viewModel::removeDevice,
            )
        }
    }
}

@Composable
private fun NotificationsStateContent(
    uiState: NotificationsUiState,
    onRetry: () -> Unit,
    content: @Composable (NotificationsContentState) -> Unit,
) {
    when (uiState) {
        is NotificationsUiState.Loading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        is NotificationsUiState.Error -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = uiState.message,
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Spacer(Modifier.height(NooraSpacing.Spacing6))
                    TextButton(onClick = onRetry) {
                        Text(stringResource(R.string.retry))
                    }
                }
            }
        }
        is NotificationsUiState.Success -> content(uiState.content)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun NotificationsScaffold(
    title: String,
    onBack: () -> Unit,
    snackbarHostState: SnackbarHostState = remember { SnackbarHostState() },
    content: @Composable () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(Modifier.padding(padding)) { content() }
    }
}

@Composable
internal fun NotificationsContent(
    state: NotificationsContentState,
    permissionStatus: NotificationPermissionStatus,
    onRequestPermission: () -> Unit,
    onOpenSettings: () -> Unit,
    onDeviceEnabledChange: (Boolean) -> Unit,
    onAccountEnabledChange: (accountHandle: String, enabled: Boolean) -> Unit,
    onResetProject: (accountHandle: String, projectHandle: String) -> Unit,
    onRemoveDevice: (PushDevice) -> Unit,
) {
    var deviceToRemove by remember { mutableStateOf<PushDevice?>(null) }

    deviceToRemove?.let { device ->
        AlertDialog(
            onDismissRequest = { deviceToRemove = null },
            title = { Text(stringResource(R.string.notifications_remove_device_title)) },
            text = { Text(stringResource(R.string.notifications_remove_device_message, deviceDisplayName(device))) },
            confirmButton = {
                TextButton(onClick = {
                    deviceToRemove = null
                    onRemoveDevice(device)
                }) {
                    Text(stringResource(R.string.notifications_remove), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deviceToRemove = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = NooraSpacing.Spacing6),
    ) {
        Spacer(Modifier.height(NooraSpacing.Spacing4))

        if (state.isPushAvailable) {
            SectionTitle(stringResource(R.string.notifications_section_permission))
            SectionCard {
                PermissionSection(permissionStatus, onRequestPermission, onOpenSettings)
            }
            Spacer(Modifier.height(NooraSpacing.Spacing5))
        }

        SectionTitle(stringResource(R.string.notifications_section_this_device))
        SectionCard {
            SwitchRow(
                title = stringResource(R.string.notifications_on_this_device),
                subtitle = stringResource(
                    if (state.isPushAvailable) {
                        R.string.notifications_on_this_device_description
                    } else {
                        R.string.notifications_unavailable_in_build
                    },
                ),
                checked = state.isPushAvailable && state.isDeviceEnabled,
                enabled = state.isPushAvailable && !state.isUpdatingDevice &&
                    (state.isDeviceEnabled || permissionStatus != NotificationPermissionStatus.Blocked),
                onCheckedChange = onDeviceEnabledChange,
            )
        }

        Spacer(Modifier.height(NooraSpacing.Spacing5))

        SectionTitle(stringResource(R.string.notifications_new_previews))
        SectionCard {
            if (state.accounts.isEmpty()) {
                Text(
                    text = stringResource(R.string.notifications_no_accounts),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(NooraSpacing.Spacing6),
                )
            }
            state.accounts.forEachIndexed { index, account ->
                if (index > 0) Divider()
                AccountRow(
                    account = account,
                    isPersonal = account.handle == state.personalAccountHandle,
                    onEnabledChange = { onAccountEnabledChange(account.handle, it) },
                )
                ProjectExceptions(
                    projects = account.projects.filter { it.setting != ProjectNotificationSetting.Default },
                    onReset = { onResetProject(account.handle, it) },
                )
            }
        }
        PreferencesFooter()

        Spacer(Modifier.height(NooraSpacing.Spacing5))

        SectionTitle(stringResource(R.string.notifications_section_devices))
        SectionCard {
            if (state.devices.isEmpty()) {
                Text(
                    text = stringResource(R.string.notifications_no_devices),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(NooraSpacing.Spacing6),
                )
            }
            state.devices.forEachIndexed { index, device ->
                if (index > 0) Divider()
                DeviceRow(
                    device = device,
                    isCurrent = device.installationId == state.currentInstallationId,
                    onRemove = { deviceToRemove = device },
                )
            }
        }

        Spacer(Modifier.height(NooraSpacing.Spacing8))
    }
}

@Composable
private fun PermissionSection(
    status: NotificationPermissionStatus,
    onRequestPermission: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Column(Modifier.padding(NooraSpacing.Spacing6)) {
        when (status) {
            NotificationPermissionStatus.Granted -> {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Spacer(Modifier.width(NooraSpacing.Spacing4))
                    Text(stringResource(R.string.notifications_permission_granted), style = MaterialTheme.typography.bodyLarge)
                }
            }
            NotificationPermissionStatus.NotGranted -> {
                Text(stringResource(R.string.notifications_permission_not_granted), style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(NooraSpacing.Spacing5))
                Button(onClick = onRequestPermission) {
                    Text(stringResource(R.string.notifications_allow))
                }
            }
            NotificationPermissionStatus.Blocked -> {
                Text(stringResource(R.string.notifications_permission_blocked), style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.height(NooraSpacing.Spacing5))
                Button(onClick = onOpenSettings) {
                    Text(stringResource(R.string.notifications_open_settings))
                }
            }
        }
    }
}

@Composable
private fun DeviceRow(device: PushDevice, isCurrent: Boolean, onRemove: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .padding(start = NooraSpacing.Spacing6, end = NooraSpacing.Spacing2),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            Modifier
                .weight(1f)
                .padding(vertical = NooraSpacing.Spacing5),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = deviceDisplayName(device),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                )
                if (isCurrent) {
                    Spacer(Modifier.width(NooraSpacing.Spacing4))
                    Text(
                        text = stringResource(R.string.notifications_this_device),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier
                            .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(8.dp))
                            .padding(horizontal = NooraSpacing.Spacing3, vertical = NooraSpacing.Spacing1),
                    )
                }
            }
            Spacer(Modifier.height(NooraSpacing.Spacing1))
            Text(
                text = stringResource(
                    R.string.notifications_device_details,
                    platformName(device.platform),
                    formatLastSeen(device.lastSeenAt),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (!isCurrent) {
            IconButton(onClick = onRemove) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.notifications_remove_device_title),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AccountRow(
    account: AccountNotificationPreference,
    isPersonal: Boolean,
    onEnabledChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(account.handle) },
        supportingContent = {
            Text(
                stringResource(
                    if (isPersonal) R.string.notifications_account_personal else R.string.notifications_account_organization,
                ),
            )
        },
        trailingContent = { Switch(checked = account.enabled, onCheckedChange = null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.toggleable(value = account.enabled, role = Role.Switch, onValueChange = onEnabledChange),
    )
}

/** Projects whose setting differs from the account's choice; closing a chip resets it to follow the account. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProjectExceptions(projects: List<ProjectNotificationPreference>, onReset: (projectHandle: String) -> Unit) {
    if (projects.isEmpty()) return
    FlowRow(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = NooraSpacing.Spacing6, end = NooraSpacing.Spacing6, bottom = NooraSpacing.Spacing4),
        horizontalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing4),
    ) {
        Text(
            text = stringResource(R.string.notifications_except),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.align(Alignment.CenterVertically),
        )
        projects.forEach { project ->
            InputChip(
                selected = false,
                onClick = { onReset(project.handle) },
                label = {
                    Text(
                        stringResource(
                            if (project.setting == ProjectNotificationSetting.On) {
                                R.string.notifications_project_on
                            } else {
                                R.string.notifications_project_off
                            },
                            project.handle,
                        ),
                    )
                },
                trailingIcon = {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = stringResource(R.string.notifications_reset_project, project.handle),
                        modifier = Modifier.size(InputChipDefaults.IconSize),
                    )
                },
            )
        }
    }
}

@Composable
private fun PreferencesFooter() {
    Text(
        text = stringResource(R.string.notifications_preferences_footer),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = NooraSpacing.Spacing2, vertical = NooraSpacing.Spacing3),
    )
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(NooraSpacing.Spacing6),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(NooraSpacing.Spacing1))
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(NooraSpacing.Spacing5))
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = NooraSpacing.Spacing2, bottom = NooraSpacing.Spacing3),
    )
}

@Composable
private fun SectionCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        content()
    }
}

@Composable
private fun Divider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)
}

@Composable
private fun deviceDisplayName(device: PushDevice): String =
    device.name?.takeIf { it.isNotBlank() }
        ?: stringResource(R.string.notifications_unnamed_device, platformName(device.platform))

private fun platformName(platform: String): String = when (platform) {
    "ios" -> "iOS"
    "android" -> "Android"
    else -> platform
}

@Composable
private fun formatLastSeen(lastSeenAt: OffsetDateTime): String {
    val duration = Duration.between(lastSeenAt, OffsetDateTime.now())
    return when {
        duration.toMinutes() < 1 -> stringResource(R.string.notifications_last_seen_now)
        duration.toMinutes() < 60 -> stringResource(R.string.notifications_last_seen_minutes, duration.toMinutes())
        duration.toHours() < 24 -> stringResource(R.string.notifications_last_seen_hours, duration.toHours())
        else -> stringResource(R.string.notifications_last_seen_days, duration.toDays())
    }
}
