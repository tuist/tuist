package dev.tuist.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.tuist.app.R
import dev.tuist.app.ui.noora.NooraSpacing
import dev.tuist.app.ui.previews.PreviewRow
import dev.tuist.app.ui.previews.PreviewsUiState
import dev.tuist.app.ui.previews.PreviewsViewModel
import dev.tuist.app.ui.previews.ProjectDropdown

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeDashboard(
    viewModel: PreviewsViewModel,
    activityViewModel: HomeActivityViewModel,
    onSeeAllPreviews: () -> Unit,
    onPreviewClick: (previewId: String, fullHandle: String) -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isRefreshing by viewModel.isRefreshing.collectAsStateWithLifecycle()
    val projectContext by viewModel.projectContext.collectAsStateWithLifecycle()
    val activity by activityViewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(viewModel) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.home_title)) },
                actions = {
                    projectContext.selectedProject?.let { selected ->
                        ProjectDropdown(projectContext.projects, selected, viewModel::selectProject)
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing || (activity.fullHandle == projectContext.selectedProject?.fullName && activity.isRefreshing),
            onRefresh = { viewModel.refresh(); activityViewModel.refresh() },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(NooraSpacing.Spacing6),
                verticalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing6),
            ) {
                projectContext.selectedProject?.let { selected ->
                    item(key = "home_activity") {
                        HomeActivityCards(activity, selected.fullName, activityViewModel::retry, activityViewModel::refresh)
                    }
                }
                item(key = "recent_previews") {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(20.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                    ) {
                        Column(modifier = Modifier.padding(NooraSpacing.Spacing6)) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing5),
                            ) {
                                Icon(
                                    painterResource(R.drawable.ic_device_mobile),
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.primary,
                                )
                                Column {
                                    Text(
                                        stringResource(R.string.recent_previews),
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                    Text(
                                        stringResource(R.string.latest_shared_apps),
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }

                            when (val state = uiState) {
                                is PreviewsUiState.Loading -> Box(
                                    modifier = Modifier.fillMaxWidth().padding(NooraSpacing.Spacing8),
                                    contentAlignment = Alignment.Center,
                                ) { CircularProgressIndicator() }
                                is PreviewsUiState.Success -> {
                                    if (state.recentPreviews.isEmpty()) {
                                        HomeMessage(stringResource(R.string.no_previews), viewModel::refresh)
                                    } else {
                                        state.recentPreviews.forEach { preview ->
                                            PreviewRow(preview, compact = true) {
                                                onPreviewClick(preview.id, state.selectedProject.fullName)
                                            }
                                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                                        }
                                    }
                                }
                                is PreviewsUiState.Empty -> HomeMessage(
                                    stringResource(
                                        if (state.message == "no_projects") R.string.no_projects else R.string.no_previews,
                                    ),
                                    viewModel::refresh,
                                )
                                is PreviewsUiState.Error -> HomeMessage(state.message, viewModel::loadProjects)
                            }

                            TextButton(
                                onClick = onSeeAllPreviews,
                                modifier = Modifier.fillMaxWidth(),
                                contentPadding = PaddingValues(vertical = NooraSpacing.Spacing5),
                            ) {
                                Text(stringResource(R.string.view_all_previews))
                                Spacer(Modifier.weight(1f))
                                Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HomeMessage(message: String, onRetry: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = NooraSpacing.Spacing6),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant)
        TextButton(onClick = onRetry) { Text(stringResource(R.string.refresh)) }
    }
}
