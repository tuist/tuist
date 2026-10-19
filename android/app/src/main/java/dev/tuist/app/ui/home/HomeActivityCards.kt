package dev.tuist.app.ui.home

import android.content.Intent
import android.text.format.DateUtils
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import dev.tuist.app.R
import dev.tuist.app.data.home.HomeActivityFailure
import dev.tuist.app.data.home.HomeActivityKind

@Composable
internal fun HomeActivityCards(
    state: HomeActivityUiState,
    selectedFullHandle: String,
    onRetry: (HomeActivityKind) -> Unit,
    onRefresh: () -> Unit,
) {
    val sections = if (state.fullHandle == selectedFullHandle) state.sections else emptyMap()
    val commonError = sections.values.firstOrNull()?.error?.takeIf { error ->
        sections.size == HomeActivityKind.entries.size && sections.values.all { it.items.isEmpty() && it.error == error }
    }
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val openDetails = stringResource(R.string.home_open_details)

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (commonError != null) {
            Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
                Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.home_activity), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(commonError.messageResource), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    TextButton(onClick = onRefresh) { Text(stringResource(R.string.retry)) }
                }
            }
        } else {
            HomeActivityKind.entries.forEach { kind ->
                val section = sections[kind] ?: HomeActivitySection(isLoading = true)
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(20.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
                ) {
                    Column(Modifier.padding(20.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Icon(
                                if (kind == HomeActivityKind.FlakyTests) Icons.Default.Warning else Icons.Default.Close,
                                contentDescription = null,
                                tint = if (kind == HomeActivityKind.FlakyTests) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.error,
                            )
                            Column {
                                Text(stringResource(kind.titleResource), style = MaterialTheme.typography.titleMedium)
                                Text(stringResource(R.string.home_last_seven_days), style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Spacer(Modifier.weight(1f))
                            if (section.isLoading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        }
                        section.items.forEach { item ->
                            HorizontalDivider(Modifier.padding(top = 16.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(
                                    Modifier.weight(1f).clickable(onClickLabel = openDetails) { uriHandler.openUri(item.url) }
                                        .padding(vertical = 16.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Text(item.title.ifBlank { openDetails }, style = MaterialTheme.typography.titleSmall,
                                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    if (item.subtitle.isNotBlank()) Text(item.subtitle, style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(
                                        DateUtils.getRelativeTimeSpanString(item.occurredAt * 1000, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString(),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                IconButton(onClick = {
                                    val share = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, item.url)
                                    context.startActivity(Intent.createChooser(share, null))
                                }) {
                                    Icon(Icons.Default.Share, contentDescription = stringResource(R.string.home_share, item.title))
                                }
                            }
                        }
                        if (section.error != null) {
                            Text(stringResource(section.error.messageResource), Modifier.padding(top = 16.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                            TextButton(onClick = { onRetry(kind) }) { Text(stringResource(R.string.retry)) }
                        } else if (section.items.isEmpty() && section.hasLoaded) {
                            Text(stringResource(kind.emptyResource), Modifier.padding(top = 16.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

private val HomeActivityKind.titleResource: Int
    get() = when (this) {
        HomeActivityKind.BuildFailures -> R.string.home_build_failures
        HomeActivityKind.TestFailures -> R.string.home_test_failures
        HomeActivityKind.FlakyTests -> R.string.home_new_flaky_tests
    }

private val HomeActivityKind.emptyResource: Int
    get() = when (this) {
        HomeActivityKind.BuildFailures -> R.string.home_no_build_failures
        HomeActivityKind.TestFailures -> R.string.home_no_test_failures
        HomeActivityKind.FlakyTests -> R.string.home_no_new_flaky_tests
    }

private val HomeActivityFailure.messageResource: Int
    get() = when (this) {
        HomeActivityFailure.Unavailable -> R.string.home_activity_unavailable
        HomeActivityFailure.Unsupported -> R.string.home_activity_unsupported
        HomeActivityFailure.Forbidden -> R.string.home_activity_forbidden
        HomeActivityFailure.InvalidResponse -> R.string.home_activity_invalid
    }
