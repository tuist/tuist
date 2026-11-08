package dev.tuist.app.ui.jams

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.tuist.app.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun JamSheets(
    sheet: JamSheet,
    state: JamsState,
    onAction: (JamAction) -> Unit,
) {
    ModalBottomSheet(
        onDismissRequest = { onAction(JamAction.Sheet(null)) },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(Modifier.fillMaxWidth().heightIn(max = 740.dp).imePadding()) {
            Column(
                Modifier.weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                when (sheet) {
                    JamSheet.NEW -> NewJam(state, onAction)
                    JamSheet.MODELS -> ModelPicker(state, onAction)
                    JamSheet.REPOSITORIES -> {
                        SheetTitle(R.string.threads_repository)
                        Text(
                            stringResource(R.string.threads_repository_description),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        ListItem(
                            headlineContent = {
                                Text(stringResource(R.string.threads_no_repository))
                            },
                            supportingContent = {
                                Text(stringResource(R.string.threads_no_repository_description))
                            },
                            modifier =
                                Modifier.clickable { onAction(JamAction.Repository(null)) },
                        )
                        if (state.repositoryError)
                            Text(
                                stringResource(R.string.threads_repositories_error),
                                color = MaterialTheme.colorScheme.error,
                            )
                        state.repositories.forEach { repository ->
                            ListItem(
                                headlineContent = { Text(repository.fullName) },
                                supportingContent = { Text(repository.defaultBranch) },
                                modifier =
                                    Modifier.clickable {
                                        onAction(JamAction.Repository(repository))
                                    },
                            )
                        }
                    }
                    JamSheet.DETAILS ->
                        state.selected?.let { jam ->
                            SheetTitle(R.string.threads_details)
                            Detail(R.string.threads_account, state.account)
                            Detail(
                                R.string.threads_repository,
                                jam.repository.ifBlank {
                                    stringResource(R.string.threads_no_repository)
                                },
                            )
                            Detail(R.string.threads_branch, jam.branch)
                            Detail(
                                R.string.threads_provider,
                                jam.provider ?: stringResource(R.string.threads_not_recorded),
                            )
                            Detail(
                                R.string.threads_model,
                                jam.model ?: stringResource(R.string.threads_not_recorded),
                            )
                            Text(
                                stringResource(R.string.threads_model_immutable),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    JamSheet.SHIP -> ShipReview(state)
                }
            }
            if (sheet == JamSheet.NEW)
                Button(
                    onClick = { onAction(JamAction.Create) },
                    modifier =
                        Modifier.fillMaxWidth()
                            .padding(horizontal = 24.dp)
                            .padding(bottom = 16.dp)
                            .height(52.dp),
                    enabled =
                        state.draft.isNotBlank() &&
                            state.model in state.models &&
                            state.model != null &&
                            !state.catalogLoading &&
                            !state.catalogError &&
                            !state.busy,
                ) {
                    if (state.busy)
                        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Text(stringResource(R.string.threads_start))
                }
            if (sheet == JamSheet.SHIP)
                Button(
                    onClick = { onAction(JamAction.ApproveShip) },
                    enabled = !state.sample && !state.busy && state.preview != null,
                    modifier =
                        Modifier.fillMaxWidth()
                            .padding(horizontal = 24.dp)
                            .padding(bottom = 16.dp)
                            .height(52.dp),
                ) {
                    Text(stringResource(R.string.threads_approve_ship))
                }
        }
    }
}

@Composable
private fun NewJam(state: JamsState, onAction: (JamAction) -> Unit) {
    SheetTitle(R.string.threads_new)
    Text(
        stringResource(R.string.threads_new_description),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    OutlinedTextField(
        value = state.draft,
        onValueChange = { onAction(JamAction.Draft(it)) },
        placeholder = { Text(stringResource(R.string.threads_prompt)) },
        minLines = 3,
        maxLines = 8,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        enabled = !state.busy,
    )
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column {
            ListItem(
                headlineContent = { Text(stringResource(R.string.threads_repository)) },
                supportingContent = {
                    Text(
                        state.repository?.fullName ?: stringResource(R.string.threads_no_repository)
                    )
                },
                leadingContent = { Icon(Icons.Default.Build, null) },
                trailingContent = { Icon(Icons.Default.KeyboardArrowRight, null) },
                modifier =
                    Modifier.clickable(enabled = !state.busy) {
                        onAction(JamAction.Sheet(JamSheet.REPOSITORIES))
                    },
            )
            HorizontalDivider(
                Modifier.padding(horizontal = 16.dp),
                color = MaterialTheme.colorScheme.outlineVariant,
            )
            ListItem(
                headlineContent = { Text(stringResource(R.string.threads_model)) },
                supportingContent = {
                    Text(state.model?.name ?: stringResource(R.string.threads_select_model))
                },
                leadingContent = { Icon(Icons.Default.Star, null) },
                trailingContent = { Icon(Icons.Default.KeyboardArrowRight, null) },
                modifier =
                    Modifier.clickable(enabled = !state.busy) {
                        onAction(JamAction.Sheet(JamSheet.MODELS))
                    },
            )
        }
    }
    CatalogNotice(state, onAction)
    Text(
        stringResource(R.string.threads_private_description),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun ModelPicker(state: JamsState, onAction: (JamAction) -> Unit) {
    SheetTitle(R.string.threads_choose_model)
    Text(
        stringResource(R.string.threads_model_description),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    CatalogNotice(state, onAction)
    state.models
        .groupBy { it.provider }
        .forEach { (provider, models) ->
            Text(
                provider,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            models.forEach { model ->
                ListItem(
                    headlineContent = { Text(model.name) },
                    supportingContent = { Text(model.id) },
                    trailingContent = { if (model == state.model) Icon(Icons.Default.Check, null) },
                    modifier = Modifier.clickable { onAction(JamAction.Model(model)) },
                )
            }
        }
    TextButton(onClick = { onAction(JamAction.Sheet(JamSheet.NEW)) }) {
        Text(stringResource(R.string.threads_back))
    }
}

@Composable
private fun CatalogNotice(state: JamsState, onAction: (JamAction) -> Unit) {
    if (state.catalogLoading)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text(
                stringResource(R.string.threads_models_loading),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    else if (state.catalogError) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
        ) {
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        stringResource(R.string.threads_models_error_title),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        stringResource(R.string.threads_models_error_description),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = { onAction(JamAction.RetryModels) }) {
                    Icon(Icons.Default.Refresh, stringResource(R.string.threads_try_again))
                }
            }
        }
    } else if (state.models.isEmpty()) {
        Text(
            stringResource(R.string.threads_models_empty),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    if (state.modelErrors.isNotEmpty() && !state.catalogLoading && !state.catalogError) {
        Text(
            stringResource(R.string.threads_models_partial),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ShipReview(state: JamsState) {
    val preview = state.preview ?: return
    SheetTitle(R.string.threads_review_ship)
    Text(
        stringResource(R.string.threads_ship_description),
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Detail(R.string.threads_repository, preview.repository)
    Detail(R.string.threads_branch, preview.targetBranch)
    Detail(R.string.threads_ship_mode, preview.mode)
    Detail(R.string.threads_base, preview.baseSha)
    Detail(R.string.threads_head, preview.headSha)
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Text(
            preview.diff,
            Modifier.fillMaxWidth().padding(16.dp),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
        )
    }
    if (state.sample)
        Text(
            stringResource(R.string.threads_sample_ship_disabled),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
}

@Composable
private fun SheetTitle(title: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.headlineSmall,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
private fun Detail(label: Int, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            stringResource(label),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}
