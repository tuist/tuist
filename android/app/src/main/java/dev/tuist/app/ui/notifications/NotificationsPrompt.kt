package dev.tuist.app.ui.notifications

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.R
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.ui.noora.NooraSpacing
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject

@HiltViewModel
class NotificationsPromptViewModel @Inject constructor(
    @ApplicationContext context: Context,
    private val pushRegistrationManager: PushRegistrationManager,
) : ViewModel() {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _isOffered = MutableStateFlow(
        pushRegistrationManager.isAvailable &&
            pushRegistrationManager.isDeviceEnabled &&
            !prefs.getBoolean(KEY_PROMPT_DISMISSED, false),
    )
    val isOffered: StateFlow<Boolean> = _isOffered.asStateFlow()

    fun dismiss() {
        prefs.edit().putBoolean(KEY_PROMPT_DISMISSED, true).apply()
        _isOffered.value = false
    }

    fun onPermissionGranted() {
        pushRegistrationManager.requestSync(force = true)
    }

    private companion object {
        const val KEY_PROMPT_DISMISSED = "previews_prompt_dismissed"
    }
}

/** Dismissible in-context invitation to allow notifications, shown on the previews list. */
@Composable
fun NotificationsPrompt(
    modifier: Modifier = Modifier,
    viewModel: NotificationsPromptViewModel = hiltViewModel(),
) {
    val isOffered by viewModel.isOffered.collectAsStateWithLifecycle()
    val permission = rememberNotificationPermissionState(onGranted = viewModel::onPermissionGranted)
    if (!isOffered || permission.status == NotificationPermissionStatus.Granted) return

    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            Column(
                Modifier
                    .weight(1f)
                    .padding(start = NooraSpacing.Spacing6, top = NooraSpacing.Spacing6),
            ) {
                Text(
                    text = stringResource(R.string.notifications_prompt_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = stringResource(R.string.notifications_prompt_message),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                TextButton(
                    onClick = {
                        if (permission.status == NotificationPermissionStatus.NotGranted) {
                            permission.request()
                        } else {
                            permission.openSettings()
                        }
                    },
                ) {
                    Text(stringResource(R.string.notifications_prompt_action))
                }
            }
            IconButton(onClick = viewModel::dismiss) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.notifications_prompt_dismiss))
            }
        }
    }
}
