package dev.tuist.app.ui.jams

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.tuist.app.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ColumnScope.JamConversation(state: JamsState, onAction: (JamAction) -> Unit) {
    val jam = state.selected ?: return
    var menu by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    LaunchedEffect(jam.id, jam.messages.lastOrNull()?.id) {
        if (jam.messages.isNotEmpty())
            listState.animateScrollToItem(
                jam.messages.lastIndex + if (jam.hasMore == true) 1 else 0
            )
    }
    TopAppBar(
        title = {
            Column {
                Text(
                    jam.title,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    jam.repository.ifEmpty { stringResource(R.string.threads_no_repository) },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        navigationIcon = {
            IconButton(onClick = { onAction(JamAction.Back) }, enabled = !state.busy) {
                Icon(Icons.Default.ArrowBack, stringResource(R.string.threads_back))
            }
        },
        actions = {
            if (jam.repository.isNotBlank())
                TextButton(
                    onClick = { onAction(JamAction.PreviewShip) },
                    enabled = jam.canMessage() && !state.busy,
                ) {
                    Text(stringResource(R.string.threads_ship))
                }
            Box {
                IconButton(onClick = { menu = true }) {
                    Icon(Icons.Default.MoreVert, stringResource(R.string.threads_actions))
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.threads_details)) },
                        onClick = {
                            menu = false
                            onAction(JamAction.Sheet(JamSheet.DETAILS))
                        },
                    )
                    DropdownMenuItem(
                        text = {
                            Text(
                                stringResource(
                                    if (jam.archiveStatus == "archived") R.string.threads_restore
                                    else R.string.threads_archive
                                )
                            )
                        },
                        onClick = {
                            menu = false
                            onAction(JamAction.Archive)
                        },
                        enabled = !state.busy,
                    )
                }
            }
        },
    )
    LazyColumn(
        Modifier.weight(1f).fillMaxWidth(),
        state = listState,
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        if (jam.hasMore == true)
            item {
                TextButton(onClick = { onAction(JamAction.LoadMore) }, enabled = !state.busy) {
                    Text(stringResource(R.string.threads_earlier))
                }
            }
        items(jam.messages, key = { it.id }) { message ->
            when (message.role) {
                "user" ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        Surface(
                            shape = RoundedCornerShape(20.dp, 20.dp, 4.dp, 20.dp),
                            color = MaterialTheme.colorScheme.primaryContainer,
                            modifier = Modifier.widthIn(max = 320.dp),
                        ) {
                            SelectionContainer {
                                Text(
                                    message.content,
                                    Modifier.padding(16.dp),
                                    style = MaterialTheme.typography.bodyLarge,
                                )
                            }
                        }
                    }
                "tool" -> {
                    var expanded by remember(message.id) { mutableStateOf(false) }
                    OutlinedCard(
                        onClick = { expanded = !expanded },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Row(
                            Modifier.padding(14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                Icons.Default.Build,
                                null,
                                Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Spacer(Modifier.width(10.dp))
                            Text(
                                message.toolName ?: stringResource(R.string.threads_tool),
                                Modifier.weight(1f),
                                style = MaterialTheme.typography.labelLarge,
                            )
                            Icon(
                                if (expanded) Icons.Default.KeyboardArrowUp
                                else Icons.Default.KeyboardArrowDown,
                                stringResource(R.string.threads_tool_details),
                            )
                        }
                        if (expanded)
                            SelectionContainer {
                                Text(
                                    message.content,
                                    Modifier.padding(14.dp),
                                    style = MaterialTheme.typography.bodySmall,
                                    fontFamily = FontFamily.Monospace,
                                )
                            }
                    }
                }
                else ->
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (message.role == "assistant")
                            Text(
                                stringResource(R.string.threads_assistant),
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.primary,
                                fontWeight = FontWeight.Bold,
                            )
                        SelectionContainer {
                            Text(
                                message.content,
                                style = MaterialTheme.typography.bodyLarge,
                                color =
                                    if (message.role == "system")
                                        MaterialTheme.colorScheme.onSurfaceVariant
                                    else MaterialTheme.colorScheme.onSurface,
                            )
                        }
                    }
            }
        }
        item { JamStatus(jam.status) }
    }
    if (jam.archiveStatus == "archived") {
        Text(
            stringResource(R.string.threads_archived_notice),
            Modifier.padding(20.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    } else {
        val suggestions =
            jam.messages.lastOrNull { it.role == "assistant" }?.suggestions.orEmpty().take(3)
        if (suggestions.isNotEmpty())
            Row(
                Modifier.fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                suggestions.forEach { suggestion ->
                    SuggestionChip(
                        onClick = { onAction(JamAction.Reply(suggestion)) },
                        label = { Text(suggestion) },
                        enabled = !state.busy && jam.canMessage(),
                    )
                }
            }
        Row(
            Modifier.fillMaxWidth().imePadding().padding(12.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedTextField(
                value = state.reply,
                onValueChange = { onAction(JamAction.Reply(it)) },
                placeholder = { Text(stringResource(R.string.threads_message)) },
                modifier = Modifier.weight(1f),
                maxLines = 5,
                shape = RoundedCornerShape(24.dp),
                enabled = !state.busy && jam.canMessage(),
            )
            FilledIconButton(
                onClick = { onAction(JamAction.Send) },
                enabled = !state.busy && jam.canMessage() && state.reply.isNotBlank(),
                modifier = Modifier.size(52.dp),
            ) {
                Icon(Icons.Default.Send, stringResource(R.string.threads_send))
            }
        }
    }
}
