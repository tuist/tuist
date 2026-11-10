package dev.tuist.app.ui.threads

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
import dev.tuist.app.data.threads.ServerThread
import dev.tuist.app.data.threads.ThreadModel
import dev.tuist.app.data.threads.ThreadRepository
import dev.tuist.app.ui.noora.LocalNooraColors

sealed interface ThreadAction {
    data class Sheet(val value: ThreadSheet?) : ThreadAction

    data class Open(val thread: ServerThread) : ThreadAction

    data class Draft(val value: String) : ThreadAction

    data class Reply(val value: String) : ThreadAction

    data class Model(val value: ThreadModel) : ThreadAction

    data class Repository(val value: ThreadRepository?) : ThreadAction

    data class Archived(val value: Boolean) : ThreadAction

    data object Back : ThreadAction

    data object Refresh : ThreadAction

    data object RetryModels : ThreadAction

    data object Create : ThreadAction

    data object Send : ThreadAction

    data class Archive(val thread: ServerThread) : ThreadAction

    data object LoadMore : ThreadAction

    data object PreviewShip : ThreadAction

    data object ApproveShip : ThreadAction

    data object DismissError : ThreadAction
}

@Composable
fun ThreadsScreen(viewModel: ThreadsViewModel = hiltViewModel()) {
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
    ThreadsContent(state) { action ->
        when (action) {
            is ThreadAction.Sheet -> viewModel.sheet(action.value)
            is ThreadAction.Open -> viewModel.open(action.thread)
            is ThreadAction.Draft -> viewModel.draft(action.value)
            is ThreadAction.Reply -> viewModel.reply(action.value)
            is ThreadAction.Model -> viewModel.model(action.value)
            is ThreadAction.Repository -> viewModel.repository(action.value)
            is ThreadAction.Archived -> viewModel.archived(action.value)
            ThreadAction.Back -> viewModel.back()
            ThreadAction.Refresh -> viewModel.refresh()
            ThreadAction.RetryModels -> viewModel.loadCatalog()
            ThreadAction.Create -> viewModel.create()
            ThreadAction.Send -> viewModel.send()
            is ThreadAction.Archive -> viewModel.archive(action.thread)
            ThreadAction.LoadMore -> viewModel.loadMore()
            ThreadAction.PreviewShip -> viewModel.previewShip()
            ThreadAction.ApproveShip -> viewModel.approveShip()
            ThreadAction.DismissError -> viewModel.dismissError()
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ThreadsContent(state: ThreadsState, onAction: (ThreadAction) -> Unit) {
    var archiveTarget by remember(state.account, state.enabled, state.denied) {
        mutableStateOf<ServerThread?>(null)
    }
    val performAction: (ThreadAction) -> Unit = { action ->
        if (action is ThreadAction.Archive && action.thread.archiveStatus != "archived") {
            archiveTarget = action.thread
        } else {
            onAction(action)
        }
    }
    MaterialTheme(
        colorScheme =
            MaterialTheme.colorScheme.copy(
                onSurfaceVariant = LocalNooraColors.current.surfaceLabelSecondary
            )
    ) {
        BackHandler(state.selected != null && state.sheet == null) { onAction(ThreadAction.Back) }
        if (!state.enabled || state.denied) {
            ThreadUnavailable(
                R.string.threads_access_title,
                R.string.threads_access_description,
            )
            return@MaterialTheme
        }
        Column(Modifier.fillMaxSize()) {
            if (state.sample) {
                Surface(color = MaterialTheme.colorScheme.primaryContainer) {
                    Text(
                        stringResource(R.string.threads_sample),
                        Modifier.fillMaxWidth().padding(12.dp),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            if (state.reconnecting)
                Text(
                    stringResource(R.string.threads_reconnecting),
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            if (state.selected != null) {
                ThreadConversation(state, performAction)
            } else {
                TopAppBar(
                    title = {
                        Column {
                            Text(
                                stringResource(R.string.threads_title),
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
                            onClick = { onAction(ThreadAction.Refresh) },
                            enabled = !state.busy,
                        ) {
                            Icon(Icons.Default.Refresh, stringResource(R.string.threads_refresh))
                        }
                    },
                )
                Row(
                    Modifier.padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    FilterChip(
                        selected = !state.showArchived,
                        onClick = { onAction(ThreadAction.Archived(false)) },
                        label = { Text(stringResource(R.string.threads_active)) },
                    )
                    FilterChip(
                        selected = state.showArchived,
                        onClick = { onAction(ThreadAction.Archived(true)) },
                        label = { Text(stringResource(R.string.threads_archived)) },
                    )
                    Spacer(Modifier.weight(1f))
                    FilledTonalIconButton(
                        onClick = { onAction(ThreadAction.Sheet(ThreadSheet.NEW)) }
                    ) {
                        Icon(Icons.Default.Add, stringResource(R.string.threads_new))
                    }
                }
                val threads =
                    state.threads.filter { (it.archiveStatus == "archived") == state.showArchived }
                when {
                    state.loading ->
                        Box(
                            Modifier.weight(1f).fillMaxWidth(),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    state.error && threads.isEmpty() ->
                        ThreadUnavailable(
                            R.string.threads_load_failed,
                            R.string.threads_retry_description,
                            R.string.retry,
                            { onAction(ThreadAction.Refresh) },
                            Modifier.weight(1f),
                        )
                    threads.isEmpty() ->
                        ThreadUnavailable(
                            R.string.threads_empty,
                            R.string.threads_empty_description,
                            R.string.threads_new,
                            { onAction(ThreadAction.Sheet(ThreadSheet.NEW)) },
                            Modifier.weight(1f),
                        )
                    else ->
                        LazyColumn(
                            Modifier.weight(1f),
                            contentPadding = PaddingValues(20.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(threads, key = { it.id }) { thread ->
                                Surface(
                                    shape = RoundedCornerShape(20.dp),
                                    color = MaterialTheme.colorScheme.surfaceContainerLow,
                                    modifier =
                                        Modifier.fillMaxWidth().clickable {
                                            onAction(ThreadAction.Open(thread))
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
                                            ThreadStatus(thread.status)
                                            Spacer(Modifier.weight(1f))
                                            Icon(
                                                Icons.Default.Lock,
                                                stringResource(R.string.threads_private),
                                                modifier = Modifier.size(14.dp),
                                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                            Box {
                                                var menu by remember { mutableStateOf(false) }
                                                IconButton(
                                                    onClick = { menu = true },
                                                    enabled = !state.busy,
                                                ) {
                                                    Icon(
                                                        Icons.Default.MoreVert,
                                                        stringResource(R.string.threads_item_actions, thread.title),
                                                    )
                                                }
                                                DropdownMenu(
                                                    expanded = menu,
                                                    onDismissRequest = { menu = false },
                                                ) {
                                                    DropdownMenuItem(
                                                        text = {
                                                            Text(
                                                                stringResource(
                                                                    if (thread.archiveStatus == "archived") R.string.threads_restore
                                                                    else R.string.threads_archive
                                                                )
                                                            )
                                                        },
                                                        enabled = !state.busy,
                                                        onClick = {
                                                            menu = false
                                                            performAction(ThreadAction.Archive(thread))
                                                        },
                                                    )
                                                }
                                            }
                                        }
                                        Text(
                                            thread.title,
                                            style = MaterialTheme.typography.titleMedium,
                                            fontWeight = FontWeight.SemiBold,
                                        )
                                        Text(
                                            thread.messages.lastOrNull()?.content ?: thread.goal,
                                            maxLines = 2,
                                            overflow = TextOverflow.Ellipsis,
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                        Text(
                                            thread.repository.ifEmpty {
                                                stringResource(R.string.threads_no_repository)
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
                                        onClick = { onAction(ThreadAction.LoadMore) },
                                        enabled = !state.busy,
                                    ) {
                                        Text(stringResource(R.string.threads_load_more))
                                    }
                                }
                        }
                }
            }
        }
        state.sheet?.let { sheet -> ThreadSheets(sheet, state, onAction) }
        archiveTarget?.let { thread ->
            AlertDialog(
                onDismissRequest = { archiveTarget = null },
                title = { Text(stringResource(R.string.threads_archive_confirmation)) },
                text = { Text(stringResource(R.string.threads_archive_description)) },
                confirmButton = {
                    TextButton(
                        enabled = !state.busy,
                        onClick = {
                            archiveTarget = null
                            onAction(ThreadAction.Archive(thread))
                        },
                    ) { Text(stringResource(R.string.threads_archive)) }
                },
                dismissButton = {
                    TextButton(onClick = { archiveTarget = null }) {
                        Text(stringResource(android.R.string.cancel))
                    }
                },
            )
        }
        if (state.error && (!state.threads.isEmpty() || state.sheet != null)) {
            AlertDialog(
                onDismissRequest = { onAction(ThreadAction.DismissError) },
                title = { Text(stringResource(R.string.threads_action_failed)) },
                text = { Text(stringResource(R.string.threads_action_failed_description)) },
                confirmButton = {
                    TextButton(onClick = { onAction(ThreadAction.DismissError) }) {
                        Text(stringResource(R.string.threads_close))
                    }
                },
            )
        }
    }
}

@Composable
internal fun ThreadUnavailable(
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
internal fun ThreadStatus(status: String) {
    val label =
        when (status) {
            "idle" -> R.string.threads_ready
            "queued" -> R.string.threads_queued
            "running" -> R.string.threads_running
            "shipping" -> R.string.threads_shipping
            "failed" -> R.string.threads_failed
            "outcome_unknown" -> R.string.threads_blocked
            else -> R.string.threads_status_unknown
        }
    Text(
        stringResource(label),
        style = MaterialTheme.typography.labelMedium,
        color =
            if (status == "idle") MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
