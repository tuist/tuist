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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
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
import dev.tuist.app.data.push.NotificationRule
import dev.tuist.app.data.push.PushDevice
import dev.tuist.app.data.push.ValueMatch
import dev.tuist.app.ui.noora.NooraSpacing
import java.time.Duration
import java.time.OffsetDateTime

/** What the screen shows: the rules list, a rule being edited, or the projects picker of that rule. */
private sealed interface NotificationsPage {
    data object Rules : NotificationsPage
    data class Editor(val rule: NotificationRule) : NotificationsPage
    data class Projects(val rule: NotificationRule) : NotificationsPage
}

/**
 * Profile › Notifications. Notifications are opt-in per device, and what they're about is a list of rules: an event,
 * the conditions that narrow it down, and how to be notified.
 */
@Composable
fun NotificationsScreen(
    onBack: () -> Unit,
    viewModel: NotificationsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val permission = rememberNotificationPermissionState(onGranted = viewModel::onPermissionGranted)
    val snackbarHostState = remember { SnackbarHostState() }
    var page by remember { mutableStateOf<NotificationsPage>(NotificationsPage.Rules) }

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }
    val goBack: () -> Unit = {
        page = when (val current = page) {
            is NotificationsPage.Projects -> NotificationsPage.Editor(current.rule)
            is NotificationsPage.Editor, NotificationsPage.Rules -> NotificationsPage.Rules
        }
    }
    BackHandler(enabled = page != NotificationsPage.Rules, onBack = goBack)

    val content = (uiState as? NotificationsUiState.Success)?.content
    val current = page
    NotificationsScaffold(
        title = when (current) {
            NotificationsPage.Rules -> stringResource(R.string.notifications_title)
            is NotificationsPage.Editor ->
                stringResource(if (current.rule.id == null) R.string.notifications_new_rule else R.string.notifications_rule)
            is NotificationsPage.Projects -> stringResource(R.string.notifications_rule_projects)
        },
        onBack = { if (current == NotificationsPage.Rules) onBack() else goBack() },
        snackbarHostState = snackbarHostState,
        actions = {
            if (current is NotificationsPage.Editor) {
                TextButton(
                    onClick = { viewModel.save(current.rule) { page = NotificationsPage.Rules } },
                    enabled = current.rule.id !in content?.rulesInFlight.orEmpty(),
                ) { Text(stringResource(R.string.notifications_rule_save)) }
            }
        },
        floatingActionButton = {
            if (current == NotificationsPage.Rules && content?.isDeviceEnabled == true) {
                ExtendedFloatingActionButton(
                    onClick = { page = NotificationsPage.Editor(NotificationRule()) },
                    icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    text = { Text(stringResource(R.string.notifications_new_rule)) },
                )
            }
        },
    ) {
        NotificationsStateContent(uiState, onRetry = viewModel::load) { state ->
            when (current) {
                NotificationsPage.Rules -> NotificationsContent(
                    state = state,
                    permissionStatus = permission.status,
                    onDeviceEnabledChange = { enabled ->
                        // Turning notifications on asks for the permission first; granting it opts in.
                        if (enabled && permission.status == NotificationPermissionStatus.NotGranted) {
                            permission.request()
                        } else {
                            viewModel.setDeviceEnabled(enabled)
                        }
                    },
                    onOpenSettings = permission.openSettings,
                    onRuleClick = { page = NotificationsPage.Editor(it) },
                    onRuleEnabledChange = viewModel::setEnabled,
                    onRemoveDevice = viewModel::removeDevice,
                )
                is NotificationsPage.Editor -> RuleEditor(
                    rule = current.rule,
                    isSaving = current.rule.id in state.rulesInFlight,
                    loadOptions = viewModel::options,
                    onChange = { page = NotificationsPage.Editor(it) },
                    onProjectsClick = { page = NotificationsPage.Projects(current.rule) },
                    onDelete = { viewModel.delete(current.rule) { page = NotificationsPage.Rules } },
                )
                is NotificationsPage.Projects -> ProjectsPicker(
                    projects = state.projects,
                    selection = current.rule.projects,
                    onSelectionChange = { page = NotificationsPage.Projects(current.rule.copy(projects = it)) },
                )
            }
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
private fun NotificationsScaffold(
    title: String,
    onBack: () -> Unit,
    snackbarHostState: SnackbarHostState,
    actions: @Composable () -> Unit,
    floatingActionButton: @Composable () -> Unit,
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
                actions = { actions() },
            )
        },
        floatingActionButton = floatingActionButton,
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Box(Modifier.padding(padding)) { content() }
    }
}

@Composable
private fun NotificationsContent(
    state: NotificationsContentState,
    permissionStatus: NotificationPermissionStatus,
    onDeviceEnabledChange: (Boolean) -> Unit,
    onOpenSettings: () -> Unit,
    onRuleClick: (NotificationRule) -> Unit,
    onRuleEnabledChange: (NotificationRule, Boolean) -> Unit,
    onRemoveDevice: (PushDevice) -> Unit,
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

    NotificationsColumn {
        SectionCard {
            SwitchRow(
                title = stringResource(R.string.notifications_on_this_device),
                checked = state.isPushAvailable && state.isDeviceEnabled,
                enabled = state.isPushAvailable && !state.isUpdatingDevice && (state.isDeviceEnabled || !isBlocked),
                onCheckedChange = onDeviceEnabledChange,
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
                    modifier = Modifier.clickable(role = Role.Button, onClick = onOpenSettings),
                )
            }
            Footer(stringResource(R.string.notifications_blocked_footer))
        }

        if (!state.isDeviceEnabled) return@NotificationsColumn

        SectionSpacer()
        SectionTitle(stringResource(R.string.notifications_rules))
        if (state.rules.isEmpty()) {
            Footer(stringResource(R.string.notifications_no_rules))
        } else {
            SectionCard {
                state.rules.forEachIndexed { index, rule ->
                    if (index > 0) Divider()
                    RuleRow(
                        rule = rule,
                        enabled = rule.id !in state.rulesInFlight,
                        onClick = { onRuleClick(rule) },
                        onEnabledChange = { onRuleEnabledChange(rule, it) },
                    )
                }
            }
            Footer(stringResource(R.string.notifications_rules_footer))
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
        // Room for the floating action button.
        Spacer(Modifier.height(72.dp))
    }
}

@Composable
private fun RuleRow(
    rule: NotificationRule,
    enabled: Boolean,
    onClick: () -> Unit,
    onEnabledChange: (Boolean) -> Unit,
) {
    ListItem(
        leadingContent = {
            Icon(
                Icons.Filled.Notifications,
                contentDescription = null,
                tint = if (rule.isEnabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
            )
        },
        headlineContent = { Text(rule.title, fontWeight = FontWeight.Medium) },
        supportingContent = {
            Text(
                stringResource(
                    if (rule.isEnabled) R.string.notifications_rule_send_notification else R.string.notifications_rule_off,
                ),
            )
        },
        trailingContent = { Switch(checked = rule.isEnabled, onCheckedChange = onEnabledChange, enabled = enabled) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(enabled = enabled, onClick = onClick),
    )
}

/** A text condition the user can set from known values or with "Contains…". */
private enum class Condition(val key: String) { Track("track"), Branch("git_branch") }

@Composable
private fun RuleEditor(
    rule: NotificationRule,
    isSaving: Boolean,
    loadOptions: suspend (String, NotificationRule) -> List<String>,
    onChange: (NotificationRule) -> Unit,
    onProjectsClick: () -> Unit,
    onDelete: () -> Unit,
) {
    var trackOptions by remember { mutableStateOf(emptyList<String>()) }
    var branchOptions by remember { mutableStateOf(emptyList<String>()) }
    var editing by remember { mutableStateOf<Condition?>(null) }
    LaunchedEffect(rule.projects) {
        trackOptions = loadOptions(Condition.Track.key, rule)
        branchOptions = loadOptions(Condition.Branch.key, rule)
    }

    editing?.let { condition ->
        ContainsDialog(
            condition = condition,
            initial = (if (condition == Condition.Track) rule.track else rule.gitBranch) as? ValueMatch.Contains,
            onDismiss = { editing = null },
            onDone = { value ->
                editing = null
                val match = value.trim().takeIf { it.isNotEmpty() }?.let { ValueMatch.Contains(it) }
                onChange(if (condition == Condition.Track) rule.copy(track = match) else rule.copy(gitBranch = match))
            },
        )
    }

    NotificationsColumn {
        SectionTitle(stringResource(R.string.notifications_rule_when))
        SectionCard {
            ListItem(
                headlineContent = { Text(stringResource(R.string.notifications_rule_projects)) },
                trailingContent = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            if (rule.projects.isEmpty()) stringResource(R.string.notifications_rule_any_project) else rule.projectsText,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
                    }
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.clickable(enabled = !isSaving, onClick = onProjectsClick),
            )
        }

        SectionSpacer()
        SectionTitle(stringResource(R.string.notifications_rule_only_if))
        SectionCard {
            ConditionRow(
                title = stringResource(R.string.notifications_rule_track),
                anyLabel = stringResource(R.string.notifications_rule_any_track),
                value = rule.track,
                options = trackOptions,
                onSelect = { onChange(rule.copy(track = it)) },
                onContains = { editing = Condition.Track },
            )
            Divider()
            ConditionRow(
                title = stringResource(R.string.notifications_rule_branch),
                anyLabel = stringResource(R.string.notifications_rule_any_branch),
                value = rule.gitBranch,
                options = branchOptions,
                onSelect = { onChange(rule.copy(gitBranch = it)) },
                onContains = { editing = Condition.Branch },
            )
            Divider()
            MenuRow(
                title = stringResource(R.string.notifications_rule_published_by),
                selected = stringResource(if (rule.publishedByMe) R.string.notifications_rule_me else R.string.notifications_rule_anyone),
            ) { dismiss ->
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.notifications_rule_anyone)) },
                    onClick = { dismiss(); onChange(rule.copy(publishedByMe = false)) },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.notifications_rule_me)) },
                    onClick = { dismiss(); onChange(rule.copy(publishedByMe = true)) },
                )
            }
        }
        Footer(
            stringResource(
                if (rule.projects.isEmpty()) {
                    R.string.notifications_rule_choose_projects_footer
                } else {
                    R.string.notifications_rule_suggestions_footer
                },
            ),
        )

        SectionSpacer()
        SectionTitle(stringResource(R.string.notifications_rule_do))
        SectionCard {
            ListItem(
                leadingContent = { Icon(Icons.Filled.Notifications, contentDescription = null) },
                headlineContent = { Text(stringResource(R.string.notifications_rule_send_notification)) },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }

        if (rule.id != null) {
            SectionSpacer()
            SectionCard {
                SwitchRow(
                    title = stringResource(R.string.notifications_rule_enabled),
                    checked = rule.isEnabled,
                    enabled = !isSaving,
                    onCheckedChange = { onChange(rule.copy(isEnabled = it)) },
                )
            }
            SectionSpacer()
            SectionCard {
                ListItem(
                    leadingContent = { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                    headlineContent = {
                        Text(stringResource(R.string.notifications_rule_delete), color = MaterialTheme.colorScheme.error)
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable(enabled = !isSaving, role = Role.Button, onClick = onDelete),
                )
            }
        }
    }
}

@Composable
private fun ConditionRow(
    title: String,
    anyLabel: String,
    value: ValueMatch?,
    options: List<String>,
    onSelect: (ValueMatch?) -> Unit,
    onContains: () -> Unit,
) {
    val selected = when (value) {
        null -> anyLabel
        is ValueMatch.Is -> value.value
        is ValueMatch.Contains -> stringResource(R.string.notifications_rule_contains_value, value.value)
    }
    // Keeps a saved value that no recent preview used selectable.
    val values = if (value is ValueMatch.Is && value.value !in options) options + value.value else options
    MenuRow(title = title, selected = selected) { dismiss ->
        DropdownMenuItem(text = { Text(anyLabel) }, onClick = { dismiss(); onSelect(null) })
        values.forEach { option ->
            DropdownMenuItem(text = { Text(option) }, onClick = { dismiss(); onSelect(ValueMatch.Is(option)) })
        }
        HorizontalDivider()
        DropdownMenuItem(
            text = { Text(stringResource(R.string.notifications_rule_contains)) },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            onClick = { dismiss(); onContains() },
        )
    }
}

/** A row whose value opens a dropdown menu, like an exposed dropdown in a settings list. */
@Composable
private fun MenuRow(
    title: String,
    selected: String,
    items: @Composable (dismiss: () -> Unit) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            Box {
                Text(selected, color = MaterialTheme.colorScheme.primary)
                DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                    items { expanded = false }
                }
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable { expanded = true },
    )
}

@Composable
private fun ContainsDialog(
    condition: Condition,
    initial: ValueMatch.Contains?,
    onDismiss: () -> Unit,
    onDone: (String) -> Unit,
) {
    var text by remember { mutableStateOf(initial?.value.orEmpty()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                stringResource(
                    if (condition == Condition.Track) {
                        R.string.notifications_rule_track_contains
                    } else {
                        R.string.notifications_rule_branch_contains
                    },
                ),
            )
        },
        text = {
            Column {
                Text(stringResource(R.string.notifications_rule_contains_message))
                Spacer(Modifier.height(NooraSpacing.Spacing4))
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    placeholder = { Text("release/") },
                    singleLine = true,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onDone(text) }) { Text(stringResource(R.string.done)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun ProjectsPicker(
    projects: List<String>,
    selection: List<String>,
    onSelectionChange: (List<String>) -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val filtered = projects.filter { it.contains(query.trim(), ignoreCase = true) }
    NotificationsColumn {
        SectionCard {
            CheckRow(stringResource(R.string.notifications_rule_any_project), selection.isEmpty()) {
                onSelectionChange(emptyList())
            }
        }
        Footer(stringResource(R.string.notifications_rule_any_project_footer))
        SectionSpacer()
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
        SectionCard {
            filtered.forEachIndexed { index, project ->
                if (index > 0) Divider()
                CheckRow(project, project in selection) {
                    onSelectionChange(if (project in selection) selection - project else selection + project)
                }
            }
        }
    }
}

@Composable
private fun CheckRow(title: String, checked: Boolean, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        trailingContent = {
            if (checked) Icon(Icons.Filled.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.clickable(onClick = onClick),
    )
}

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
                    modifier = Modifier.size(24.dp),
                )
            }
        }
    }
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
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
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
