package dev.tuist.app.ui.previews

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
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
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreviewDetailScreen(
    onBack: () -> Unit,
    viewModel: PreviewDetailViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                actions = {
                    val state = uiState
                    if (state is PreviewDetailUiState.Success) {
                        IconButton(onClick = {
                            val shareUrl = "${viewModel.serverUrl}/${viewModel.fullHandle}/previews/${state.preview.id}"
                            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                                putExtra(Intent.EXTRA_TEXT, shareUrl)
                                type = "text/plain"
                            }
                            context.startActivity(Intent.createChooser(sendIntent, null))
                        }) {
                            Icon(Icons.Default.Share, contentDescription = stringResource(R.string.share))
                        }
                    }
                },
            )
        },
    ) { padding ->
        when (val state = uiState) {
            is PreviewDetailUiState.Loading -> {
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            is PreviewDetailUiState.Error -> {
                Box(
                    Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = state.message,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Spacer(Modifier.height(NooraSpacing.Spacing6))
                        TextButton(onClick = { viewModel.loadPreview() }) {
                            Text(stringResource(R.string.retry))
                        }
                    }
                }
            }
            is PreviewDetailUiState.Success -> {
                PreviewDetailContent(
                    preview = state.preview,
                    onDelete = { viewModel.deletePreview(onBack) },
                    modifier = Modifier.padding(padding),
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PreviewDetailContent(
    preview: Preview,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showDeleteConfirmation by remember { mutableStateOf(false) }

    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text(stringResource(R.string.delete_preview_title)) },
            text = { Text(stringResource(R.string.delete_preview_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirmation = false
                    onDelete()
                }) {
                    Text(
                        stringResource(R.string.delete_account_confirm),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
                    Text(stringResource(R.string.cancel))
                }
            },
        )
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = NooraSpacing.Spacing6),
    ) {
        Spacer(Modifier.height(NooraSpacing.Spacing4))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SubcomposeAsyncImage(
                model = preview.iconUrl,
                contentDescription = preview.displayName,
                modifier = Modifier
                    .size(92.dp)
                    .clip(RoundedCornerShape(20.dp)),
                error = {
                    Image(
                        painter = painterResource(R.drawable.preview_icon_placeholder),
                        contentDescription = preview.displayName,
                        contentScale = ContentScale.Fit,
                    )
                },
            )
            Spacer(Modifier.width(NooraSpacing.Spacing5))
            Column {
                Text(
                    text = preview.displayName ?: "App",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                preview.version?.let { version ->
                    Spacer(Modifier.height(NooraSpacing.Spacing1))
                    Text(
                        text = "v$version",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                val apkBuild = preview.builds.firstOrNull { it.type == AppBuild.Type.apk }
                if (apkBuild != null) {
                    Spacer(Modifier.height(NooraSpacing.Spacing3))
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
                            .padding(horizontal = 16.dp, vertical = 6.dp),
                    ) {
                        Text(
                            text = stringResource(R.string.preview_run),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(NooraSpacing.Spacing7))

        // Supported platforms
        if (preview.supportedPlatforms.isNotEmpty()) {
            Text(
                text = stringResource(R.string.preview_supported_platforms),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.height(NooraSpacing.Spacing4))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing3),
                verticalArrangement = Arrangement.spacedBy(NooraSpacing.Spacing3),
            ) {
                preview.supportedPlatforms.forEach { platform ->
                    PlatformPill(platform)
                }
            }
            Spacer(Modifier.height(NooraSpacing.Spacing7))
        }

        // Details section
        Text(
            text = stringResource(R.string.preview_details),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium,
        )
        Spacer(Modifier.height(NooraSpacing.Spacing4))

        // Created by
        MetadataRow(
            title = stringResource(R.string.preview_created_by),
            value = {
                if (preview.createdFromCi) {
                    Row(
                        modifier = Modifier
                            .background(
                                MaterialTheme.colorScheme.surfaceContainerHigh,
                                RoundedCornerShape(20.dp),
                            )
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Settings,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(NooraSpacing.Spacing2))
                        Text(
                            text = "CI",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    Row(
                        modifier = Modifier
                            .background(
                                MaterialTheme.colorScheme.surfaceContainerHigh,
                                RoundedCornerShape(20.dp),
                            )
                            .padding(horizontal = 10.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.Person,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(NooraSpacing.Spacing2))
                        Text(
                            text = preview.createdBy?.handle ?: stringResource(R.string.preview_unknown),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            },
        )
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)

        // Created at
        MetadataRow(
            title = stringResource(R.string.preview_created_at),
            value = {
                Text(
                    text = formatFullDate(preview.insertedAt),
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
            },
        )
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)

        // Bundle identifier
        preview.bundleIdentifier?.let { bundleId ->
            MetadataRow(
                title = stringResource(R.string.preview_bundle_id),
                value = {
                    Text(
                        text = bundleId,
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                    )
                },
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)
        }

        // Branch
        preview.gitBranch?.let { branch ->
            MetadataRow(
                title = stringResource(R.string.preview_branch),
                value = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            painter = painterResource(R.drawable.ic_branch),
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(NooraSpacing.Spacing1))
                        Text(
                            text = branch,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                },
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant, thickness = 0.5.dp)
        }

        // Commit SHA
        preview.gitCommitSha?.let { sha ->
            MetadataRow(
                title = stringResource(R.string.preview_commit_sha),
                value = {
                    Text(
                        text = sha.take(7),
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                    )
                },
            )
        }

        Spacer(Modifier.height(NooraSpacing.Spacing7))

        // Delete button
        Button(
            onClick = { showDeleteConfirmation = true },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                contentColor = MaterialTheme.colorScheme.error,
            ),
            shape = RoundedCornerShape(12.dp),
        ) {
            Text(
                text = stringResource(R.string.preview_delete),
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.Medium,
            )
            Spacer(Modifier.width(NooraSpacing.Spacing2))
            Icon(
                Icons.Default.Delete,
                contentDescription = null,
                modifier = Modifier.size(20.dp),
            )
        }

        Spacer(Modifier.height(NooraSpacing.Spacing8))
    }
}

@Composable
private fun MetadataRow(
    title: String,
    value: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = NooraSpacing.Spacing5),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.outline,
        )
        Spacer(Modifier.weight(1f))
        value()
    }
}

@Composable
private fun PlatformPill(platform: PreviewSupportedPlatform) {
    val label = when (platform) {
        PreviewSupportedPlatform.ios -> "iOS"
        PreviewSupportedPlatform.ios_simulator -> "iOS Simulator"
        PreviewSupportedPlatform.macos -> "macOS"
        PreviewSupportedPlatform.tvos -> "tvOS"
        PreviewSupportedPlatform.tvos_simulator -> "tvOS Simulator"
        PreviewSupportedPlatform.watchos -> "watchOS"
        PreviewSupportedPlatform.watchos_simulator -> "watchOS Simulator"
        PreviewSupportedPlatform.visionos -> "visionOS"
        PreviewSupportedPlatform.visionos_simulator -> "visionOS Simulator"
        PreviewSupportedPlatform.android -> "Android"
    }
    Row(
        modifier = Modifier
            .background(
                MaterialTheme.colorScheme.surfaceContainerHigh,
                RoundedCornerShape(20.dp),
            )
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_device_mobile),
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(NooraSpacing.Spacing2))
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun formatFullDate(isoTimestamp: String): String {
    return try {
        val dateTime = OffsetDateTime.parse(isoTimestamp, DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        dateTime.format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.FULL, FormatStyle.SHORT))
    } catch (_: Exception) {
        isoTimestamp
    }
}
