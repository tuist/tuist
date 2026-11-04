package dev.tuist.app.ui.notifications

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.tuist.app.R
import dev.tuist.app.data.push.AccountNotificationPreference
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
    // With several accounts, tapping one opens its projects in place of the account list.
    var selectedAccountHandle by rememberSaveable { mutableStateOf<String?>(null) }
    val selectedAccount = (uiState as? NotificationsUiState.Success)?.content?.accountsWithProjects
        ?.find { it.handle == selectedAccountHandle }

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }
    BackHandler(enabled = selectedAccount != null) { selectedAccountHandle = null }

    NotificationsScaffold(
        title = selectedAccount?.handle ?: stringResource(R.string.notifications_title),
        onBack = { if (selectedAccount != null) selectedAccountHandle = null else onBack() },
        snackbarHostState = snackbarHostState,
    ) {
        NotificationsStateContent(uiState, onRetry = viewModel::load) { content ->
            val actions = NotificationsActions(
                onDeviceEnabledChange = { enabled ->
                    // Turning notifications on asks for the permission first; granting it opts in.
                    if (enabled && permission.status == NotificationPermissionStatus.NotGranted) {
                        permission.request()
                    } else {
                        viewModel.setDeviceEnabled(enabled)
                    }
                },
                onOpenSettings = permission.openSettings,
                onAccountEnabledChange = viewModel::setAccountEnabled,
                onProjectEnabledChange = viewModel::setProjectEnabled,
                onAccountClick = { selectedAccountHandle = it },
                onRemoveDevice = viewModel::removeDevice,
            )
            if (selectedAccount != null) {
                AccountNotificationsContent(
                    state = content,
                    account = selectedAccount,
                    isBlocked = permission.status == NotificationPermissionStatus.Blocked,
                    actions = actions,
                )
            } else {
                NotificationsContent(state = content, permissionStatus = permission.status, actions = actions)
            }
        }
    }
}

internal class NotificationsActions(
    val onDeviceEnabledChange: (Boolean) -> Unit,
    val onOpenSettings: () -> Unit,
    val onAccountEnabledChange: (accountHandle: String, enabled: Boolean) -> Unit,
    val onProjectEnabledChange: (accountHandle: String, projectHandle: String, enabled: Boolean) -> Unit,
    val onAccountClick: (accountHandle: String) -> Unit,
    val onRemoveDevice: (PushDevice) -> Unit,
)

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
        is NotificationsUiState.Unsupported -> {
            Footer(
                stringResource(R.string.notifications_unsupported),
                Modifier.padding(horizontal = NooraSpacing.Spacing6, vertical = NooraSpacing.Spacing5),
            )
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
    actions: NotificationsActions,
) {
    var deviceToRemove by remember { mutableStateOf<PushDevice?>(null) }
    val isBlocked = permissionStatus == NotificationPermissionStatus.Blocked

    deviceToRemove?.let { device ->
        AlertDialog(
            onDismissRequest = { deviceToRemove = null },
            title = { Text(stringResource(R.string.notifications_remove_device_title)) },
            text = { Text(stringResource(R.string.notifications_remove_device_message, deviceDisplayName(device))) },
            confirmButton = {
                TextButton(onClick = {
                    deviceToRemove = null
                    actions.onRemoveDevice(device)
                }) {
                    Text(stringResource(R.string.notifications_remove), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deviceToRemove = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    NotificationsColumn {
        SectionCard {
            SwitchRow(
                title = stringResource(R.string.notifications_on_this_device),
                checked = state.isPushAvailable && state.isDeviceEnabled,
                enabled = state.isPushAvailable && !state.isUpdatingDevice && (state.isDeviceEnabled || !isBlocked),
                onCheckedChange = actions.onDeviceEnabledChange,
            )
        }
        Footer(
            stringResource(
                if (state.isPushAvailable) {
                    R.string.notifications_on_this_device_description
                } else {
                    R.string.notifications_unavailable_in_build
                },
            ),
        )

        if (state.isPushAvailable && isBlocked) {
            SectionSpacer()
            SectionCard {
                ListItem(
                    headlineContent = {
                        Text(
                            stringResource(R.string.notifications_turn_on_in_settings),
                            color = MaterialTheme.colorScheme.primary,
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable(role = Role.Button, onClick = actions.onOpenSettings),
                )
            }
            Footer(stringResource(R.string.notifications_blocked_footer))
        }

        if (!state.isDeviceEnabled) return@NotificationsColumn

        SectionSpacer()
        val accounts = state.accountsWithProjects
        when {
            accounts.isEmpty() -> {
                SectionTitle(stringResource(R.string.notifications_new_previews))
                Footer(stringResource(R.string.notifications_no_projects))
            }
            // Most people belong to one account with projects, so its projects are shown right here.
            accounts.size == 1 -> AccountPreferences(
                state = state,
                account = accounts.single(),
                title = stringResource(R.string.notifications_new_previews),
                allProjectsTitle = stringResource(R.string.notifications_all_projects_in, accounts.single().handle),
                enabled = !isBlocked,
                actions = actions,
            )
            else -> {
                SectionTitle(stringResource(R.string.notifications_new_previews))
                SectionCard {
                    accounts.forEachIndexed { index, account ->
                        if (index > 0) Divider()
                        AccountRow(
                            account = account,
                            isPersonal = account.handle == state.personalAccountHandle,
                            enabled = !isBlocked,
                            onClick = { actions.onAccountClick(account.handle) },
                        )
                    }
                }
            }
        }

        SectionSpacer()
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
        Footer(stringResource(R.string.notifications_devices_footer))
    }
}

/** The projects of one account, opened from the account list when several accounts have projects. */
@Composable
internal fun AccountNotificationsContent(
    state: NotificationsContentState,
    account: AccountNotificationPreference,
    isBlocked: Boolean,
    actions: NotificationsActions,
) {
    NotificationsColumn {
        AccountPreferences(
            state = state,
            account = account,
            title = null,
            allProjectsTitle = stringResource(R.string.notifications_all_projects),
            enabled = !isBlocked,
            actions = actions,
        )
    }
}

/** The All projects switch, then a switch per project. A project that differs from All projects is an override. */
@Composable
private fun AccountPreferences(
    state: NotificationsContentState,
    account: AccountNotificationPreference,
    title: String?,
    allProjectsTitle: String,
    enabled: Boolean,
    actions: NotificationsActions,
) {
    var query by rememberSaveable(account.handle) { mutableStateOf("") }
    val projects = account.projects.filter { it.handle.contains(query.trim(), ignoreCase = true) }

    title?.let { SectionTitle(it) }
    SectionCard {
        SwitchRow(
            title = allProjectsTitle,
            checked = account.enabled,
            enabled = enabled && account.handle !in state.changesInFlight,
            onCheckedChange = { actions.onAccountEnabledChange(account.handle, it) },
        )
    }
    Footer(stringResource(R.string.notifications_all_projects_footer))

    SectionSpacer()
    SectionTitle(stringResource(R.string.notifications_section_projects))
    if (account.projects.size > SEARCH_THRESHOLD) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            placeholder = { Text(stringResource(R.string.notifications_search_projects)) },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = NooraSpacing.Spacing4),
        )
    }
    SectionCard {
        projects.forEachIndexed { index, project ->
            if (index > 0) Divider()
            SwitchRow(
                title = project.handle,
                checked = project.enabled,
                enabled = enabled && "${account.handle}/${project.handle}" !in state.changesInFlight,
                onCheckedChange = { actions.onProjectEnabledChange(account.handle, project.handle, it) },
            )
        }
    }
}

/** Material's opacity for disabled content. */
private const val DISABLED_ALPHA = 0.38f

/** Long project lists get a search field. */
private const val SEARCH_THRESHOLD = 8

@Composable
private fun NotificationsColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = NooraSpacing.Spacing6),
    ) {
        Spacer(Modifier.height(NooraSpacing.Spacing4))
        content()
        Spacer(Modifier.height(NooraSpacing.Spacing8))
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
    enabled: Boolean,
    onClick: () -> Unit,
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
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = stringResource(
                        when (account.summary) {
                            AccountNotificationSummary.On -> R.string.notifications_summary_on
                            AccountNotificationSummary.Off -> R.string.notifications_summary_off
                            AccountNotificationSummary.Custom -> R.string.notifications_summary_custom
                        },
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier
            .clickable(enabled = enabled, onClick = onClick)
            .alpha(if (enabled) 1f else DISABLED_ALPHA),
    )
}

@Composable
private fun Footer(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.padding(horizontal = NooraSpacing.Spacing2, vertical = NooraSpacing.Spacing3),
    )
}

@Composable
private fun SectionSpacer() {
    Spacer(Modifier.height(NooraSpacing.Spacing5))
}

@Composable
private fun SwitchRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(horizontal = NooraSpacing.Spacing6, vertical = NooraSpacing.Spacing4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
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
