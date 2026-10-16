package dev.tuist.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
    onSeeAllPreviews: () -> Unit,
    onPreviewClick: (previewId: String, fullHandle: String) -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isRefreshing by viewModel.isRefreshing.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(viewModel) {
        viewModel.errorEvents.collect { snackbarHostState.showSnackbar(it) }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.home_title)) }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = { viewModel.refresh() },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = NooraSpacing.Spacing6),
            ) {
                item(key = "recent_previews_header") {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            stringResource(R.string.recent_previews),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        TextButton(onClick = onSeeAllPreviews) {
                            Text(stringResource(R.string.see_all))
                        }
                    }
                }

                when (val state = uiState) {
                    is PreviewsUiState.Loading -> item(key = "loading") {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(NooraSpacing.Spacing6),
                            contentAlignment = Alignment.Center,
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                    is PreviewsUiState.Success -> {
                        item(key = "project") {
                            ProjectDropdown(state.projects, state.selectedProject, viewModel::selectProject)
                        }
                        if (state.recentPreviews.isEmpty()) {
                            item(key = "empty") {
                                HomeMessage(stringResource(R.string.no_previews), viewModel::refresh)
                            }
                        }
                        items(state.recentPreviews, key = { it.id }) { preview ->
                            PreviewRow(preview) { onPreviewClick(preview.id, state.selectedProject.fullName) }
                            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                        }
                    }
                    is PreviewsUiState.Empty -> item(key = "empty") {
                        HomeMessage(
                            stringResource(
                                if (state.message == "no_projects") R.string.no_projects else R.string.no_previews,
                            ),
                            viewModel::refresh,
                        )
                    }
                    is PreviewsUiState.Error -> item(key = "error") {
                        HomeMessage(state.message, viewModel::loadProjects)
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
