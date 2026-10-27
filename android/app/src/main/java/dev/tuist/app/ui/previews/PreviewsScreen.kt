package dev.tuist.app.ui.previews

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.Image
import androidx.compose.ui.layout.ContentScale
import coil3.compose.SubcomposeAsyncImage
import dev.tuist.app.R
import dev.tuist.app.api.model.AppBuild
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.PreviewSupportedPlatform
import dev.tuist.app.ui.noora.NooraSpacing
import java.time.Duration
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreviewsScreen(
    onPreviewClick: (previewId: String, fullHandle: String) -> Unit = { _, _ -> },
    viewModel: PreviewsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isRefreshing by viewModel.isRefreshing.collectAsStateWithLifecycle()
    val isLoadingMore by viewModel.isLoadingMore.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(Unit) {
        viewModel.errorEvents.collect { message ->
            snackbarHostState.showSnackbar(message)
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = { viewModel.refresh() },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            when (val state = uiState) {
                is PreviewsUiState.Loading -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                is PreviewsUiState.Error -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = state.message,
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.error,
                            )
                            Spacer(Modifier.height(NooraSpacing.Spacing6))
                            TextButton(onClick = { viewModel.loadProjects() }) {
                                Text(stringResource(R.string.retry))
                            }
                        }
                    }
                }
                is PreviewsUiState.Empty -> {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(
                                text = stringResource(
                                    if (state.message == "no_projects") R.string.no_projects else R.string.no_previews,
                                ),
                                style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Spacer(Modifier.height(NooraSpacing.Spacing6))
                            TextButton(onClick = { viewModel.refresh() }) {
                                Text(stringResource(R.string.refresh))
                            }
                        }
                    }
                }
                is PreviewsUiState.Success -> {
                    PreviewsContent(
                        state = state,
                        isLoadingMore = isLoadingMore,
                        onProjectSelected = { viewModel.selectProject(it) },
                        onLoadMore = { viewModel.loadMorePreviews() },
                        onPreviewClick = { preview ->
                            onPreviewClick(preview.id, state.selectedProject.fullName)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun PreviewsContent(
    state: PreviewsUiState.Success,
    isLoadingMore: Boolean,
    onProjectSelected: (dev.tuist.app.api.model.Project) -> Unit,
    onLoadMore: () -> Unit,
    onPreviewClick: (Preview) -> Unit,
) {
    val listState = rememberLazyListState()

    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisibleItem = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            val totalItems = listState.layoutInfo.totalItemsCount
            lastVisibleItem >= totalItems - 2 && state.hasMorePreviews
        }
    }

    LaunchedEffect(shouldLoadMore) {
        if (shouldLoadMore) {
            onLoadMore()
        }
    }

    LazyColumn(
        state = listState,
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = NooraSpacing.Spacing6),
    ) {
        item(key = "header") {
            ProjectDropdown(
                projects = state.projects,
                selectedProject = state.selectedProject,
                onProjectSelected = onProjectSelected,
            )
            Spacer(Modifier.height(NooraSpacing.Spacing4))
        }

        if (state.previews.isEmpty()) {
            item(key = "empty") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = NooraSpacing.Spacing13),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = stringResource(R.string.no_previews),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        } else {
            items(state.previews, key = { it.id }) { preview ->
                PreviewRow(
                    preview = preview,
                    onClick = { onPreviewClick(preview) },
                )
                HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant,
                    thickness = 0.5.dp,
                )
            }

            if (isLoadingMore) {
                item(key = "loading_more") {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(NooraSpacing.Spacing6),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ProjectDropdown(
    projects: List<dev.tuist.app.api.model.Project>,
    selectedProject: dev.tuist.app.api.model.Project,
    onProjectSelected: (dev.tuist.app.api.model.Project) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = NooraSpacing.Spacing4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.apps_in),
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(Modifier.width(NooraSpacing.Spacing3))
        Box {
            Row(
                modifier = Modifier.clickable { expanded = true },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = selectedProject.fullName,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                Icon(
                    Icons.Default.ArrowDropDown,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
                modifier = Modifier.heightIn(max = 300.dp),
            ) {
                projects.forEach { project ->
                    DropdownMenuItem(
                        text = { Text(project.fullName) },
                        onClick = {
                            onProjectSelected(project)
                            expanded = false
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun PreviewRow(preview: Preview, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = NooraSpacing.Spacing5),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SubcomposeAsyncImage(
            model = preview.iconUrl,
            contentDescription = preview.displayName,
            modifier = Modifier
                .size(64.dp)
                .clip(RoundedCornerShape(12.dp)),
            error = {
                Image(
                    painter = painterResource(R.drawable.preview_icon_placeholder),
                    contentDescription = preview.displayName,
                    contentScale = ContentScale.Fit,
                )
            },
        )

        Spacer(Modifier.width(NooraSpacing.Spacing5))

        Column(modifier = Modifier.weight(1f)) {
            // Row 1: commit SHA
            preview.gitCommitSha?.let { sha ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        painter = painterResource(R.drawable.ic_commit),
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.width(NooraSpacing.Spacing1))
                    Text(
                        text = sha.take(7),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.height(NooraSpacing.Spacing1))
            }

            // Row 2: display name (bold)
            Text(
                text = preview.displayName ?: "Preview",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Spacer(Modifier.height(NooraSpacing.Spacing1))

            // Row 3: relative time + branch
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing5),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = formatRelativeTime(preview.insertedAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                preview.gitBranch?.let { branch ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            painter = painterResource(R.drawable.ic_branch),
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(NooraSpacing.Spacing1))
                        Text(
                            text = branch,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }

        val apkBuild = preview.builds.firstOrNull { it.type == AppBuild.Type.apk }
        if (apkBuild != null && preview.supportedPlatforms.contains(PreviewSupportedPlatform.android)) {
            Spacer(Modifier.width(NooraSpacing.Spacing4))
            val context = LocalContext.current
            Box(
                modifier = Modifier
                    .clickable {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(apkBuild.url)),
                        )
                    }
                    .background(
                        MaterialTheme.colorScheme.surfaceContainerHighest,
                        RoundedCornerShape(20.dp),
                    )
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                Text(
                    text = stringResource(R.string.preview_run),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

private fun formatRelativeTime(isoTimestamp: String): String {
    return try {
        val dateTime = OffsetDateTime.parse(isoTimestamp, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        val now = OffsetDateTime.now()
        val duration = Duration.between(dateTime, now)

        when {
            duration.toMinutes() < 1 -> "Just now"
            duration.toMinutes() < 60 -> "${duration.toMinutes()}m ago"
            duration.toHours() < 24 -> "${duration.toHours()}h ago"
            duration.toDays() < 30 -> "${duration.toDays()}d ago"
            else -> "${duration.toDays() / 30}mo ago"
        }
    } catch (_: Exception) {
        isoTimestamp
    }
}
