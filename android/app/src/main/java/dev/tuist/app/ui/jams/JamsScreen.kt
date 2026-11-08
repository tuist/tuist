package dev.tuist.app.ui.jams

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import dev.tuist.app.R
import dev.tuist.app.data.jams.ServerJam
import dev.tuist.app.data.jams.JamModel
import dev.tuist.app.data.jams.JamRepository
import dev.tuist.app.ui.noora.LocalNooraColors

sealed interface JamAction {
    data class Sheet(val value: JamSheet?) : JamAction

    data class Open(val jam: ServerJam) : JamAction

    data class Draft(val value: String) : JamAction

    data class Reply(val value: String) : JamAction

    data class Model(val value: JamModel) : JamAction

    data class Repository(val value: JamRepository?) : JamAction

    data class Archived(val value: Boolean) : JamAction

    data object Back : JamAction

    data object Refresh : JamAction

    data object RetryModels : JamAction

    data object Create : JamAction

    data object Send : JamAction

    data object Archive : JamAction

    data object LoadMore : JamAction

    data object PreviewShip : JamAction

    data object ApproveShip : JamAction

    data object DismissError : JamAction
}

@Composable
fun JamsScreen(viewModel: JamsViewModel = hiltViewModel()) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(
        viewModel,
        lifecycle,
        state.enabled,
        state.denied,
        state.account,
        state.selected?.id,
    ) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { viewModel.watch() }
    }
    JamsContent(state) { action ->
        when (action) {
            is JamAction.Sheet -> viewModel.sheet(action.value)
            is JamAction.Open -> viewModel.open(action.jam)
            is JamAction.Draft -> viewModel.draft(action.value)
            is JamAction.Reply -> viewModel.reply(action.value)
            is JamAction.Model -> viewModel.model(action.value)
            is JamAction.Repository -> viewModel.repository(action.value)
            is JamAction.Archived -> viewModel.archived(action.value)
            JamAction.Back -> viewModel.back()
            JamAction.Refresh -> viewModel.refresh()
            JamAction.RetryModels -> viewModel.loadCatalog()
            JamAction.Create -> viewModel.create()
            JamAction.Send -> viewModel.send()
            JamAction.Archive -> viewModel.archive()
            JamAction.LoadMore -> viewModel.loadMore()
            JamAction.PreviewShip -> viewModel.previewShip()
            JamAction.ApproveShip -> viewModel.approveShip()
            JamAction.DismissError -> viewModel.dismissError()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun JamsContent(state: JamsState, onAction: (JamAction) -> Unit) {
    MaterialTheme(
        colorScheme =
            MaterialTheme.colorScheme.copy(
                onSurfaceVariant = LocalNooraColors.current.surfaceLabelSecondary
            )
    ) {
        BackHandler(state.selected != null && state.sheet == null) { onAction(JamAction.Back) }
        if (!state.enabled || state.denied) {
            JamUnavailable(
                R.string.jams_access_title,
                R.string.jams_access_description,
            )
            return@MaterialTheme
        }
        Column(Modifier.fillMaxSize()) {
            if (state.sample) {
                Surface(color = MaterialTheme.colorScheme.primaryContainer) {
                    Text(
                        stringResource(R.string.jams_sample),
                        Modifier.fillMaxWidth().padding(12.dp),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            if (state.reconnecting)
                Text(
                    stringResource(R.string.jams_reconnecting),
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            if (state.selected != null) {
                JamConversation(state, onAction)
            } else {
                TopAppBar(
                    title = {
                        Column {
                            Text(
                                stringResource(R.string.jams_title),
                                fontWeight = FontWeight.Bold,
                            )
                            Text(
                                state.account,
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    actions = {
                        IconButton(
                            onClick = { onAction(JamAction.Refresh) },
                            enabled = !state.busy,
                        ) {
                            Icon(Icons.Default.Refresh, stringResource(R.string.jams_refresh))
                        }
                    },
                )
                Row(
                    Modifier.padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = !state.showArchived,
                        onClick = { onAction(JamAction.Archived(false)) },
                        label = { Text(stringResource(R.string.jams_active)) },
                    )
                    FilterChip(
                        selected = state.showArchived,
                        onClick = { onAction(JamAction.Archived(true)) },
                        label = { Text(stringResource(R.string.jams_archived)) },
                    )
                    Spacer(Modifier.weight(1f))
                    FilledTonalIconButton(
                        onClick = { onAction(JamAction.Sheet(JamSheet.NEW)) }
                    ) {
                        Icon(Icons.Default.Add, stringResource(R.string.jams_new))
                    }
                }
                val jams =
                    state.jams.filter { (it.archiveStatus == "archived") == state.showArchived }
                when {
                    state.loading ->
                        Box(
                            Modifier.weight(1f).fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    state.error && jams.isEmpty() ->
                        JamUnavailable(
                            R.string.jams_load_failed,
                            R.string.jams_retry_description,
                            R.string.retry,
                            { onAction(JamAction.Refresh) },
                            Modifier.weight(1f),
                        )
                    jams.isEmpty() ->
                        JamUnavailable(
                            R.string.jams_empty,
                            R.string.jams_empty_description,
                            R.string.jams_new,
                            { onAction(JamAction.Sheet(JamSheet.NEW)) },
                            Modifier.weight(1f),
                        )
                    else ->
                        LazyColumn(
                            Modifier.weight(1f),
                            contentPadding = PaddingValues(20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(jams, key = { it.id }) { jam ->
                                Surface(
                                    shape = RoundedCornerShape(20.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                                    modifier =
                                        Modifier.fillMaxWidth().clickable {
                                            onAction(JamAction.Open(jam))
                                        },
                                ) {
                                    Column(
                                        Modifier.padding(20.dp),
                                        verticalArrangement = Arrangement.spacedBy(10.dp),
                                    ) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Icon(
                                                painterResource(R.drawable.ic_message),
                                                null,
                                                tint = MaterialTheme.colorScheme.primary,
                                                modifier = Modifier.size(20.dp),
                                            )
                                            Spacer(Modifier.width(8.dp))
                                            JamStatus(jam.status)
                                            Spacer(Modifier.weight(1f))
                                            Icon(
                                                Icons.Default.Lock,
                                                stringResource(R.string.jams_private),
                                                modifier = Modifier.size(14.dp),
                                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                        Text(
                                            jam.title,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            jam.messages.lastOrNull()?.content ?: jam.goal,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                        Text(
                                            jam.repository.ifEmpty {
                                                stringResource(R.string.jams_no_repository)
                                            },
                                            style = MaterialTheme.typography.labelMedium,
                                            color = MaterialTheme.colorScheme.primary,
                                        )
                                    }
                                }
                            }
                            if (state.cursor != null)
                                item {
                                    TextButton(
                                        onClick = { onAction(JamAction.LoadMore) },
                                        enabled = !state.busy,
                                    ) {
                                        Text(stringResource(R.string.jams_load_more))
                                    }
                                }
                        }
                }
            }
        }
        state.sheet?.let { sheet -> JamSheets(sheet, state, onAction) }
        if (state.error && (!state.jams.isEmpty() || state.sheet != null)) {
            AlertDialog(
                onDismissRequest = { onAction(JamAction.DismissError) },
                title = { Text(stringResource(R.string.jams_action_failed)) },
                text = { Text(stringResource(R.string.jams_action_failed_description)) },
                confirmButton = {
                    TextButton(onClick = { onAction(JamAction.DismissError) }) {
                        Text(stringResource(R.string.jams_close))
                    }
                },
            )
        }
    }
}

@Composable
internal fun JamUnavailable(
    title: Int,
    description: Int,
    action: Int? = null,
    onClick: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxSize().padding(28.dp), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Icon(
                painterResource(R.drawable.ic_message),
                null,
                Modifier.size(42.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                stringResource(title),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            Text(
                stringResource(description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            if (action != null) Button(onClick = onClick) { Text(stringResource(action)) }
        }
    }
}

@Composable
internal fun JamStatus(status: String) {
    val label =
        when (status) {
            "idle" -> R.string.jams_ready
            "queued" -> R.string.jams_queued
            "running" -> R.string.jams_running
            "shipping" -> R.string.jams_shipping
            "failed" -> R.string.jams_failed
            "outcome_unknown" -> R.string.jams_blocked
            else -> R.string.jams_status_unknown
        }
    Text(
        stringResource(label),
        style = MaterialTheme.typography.labelMedium,
        color =
            if (status == "idle") MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
