package dev.tuist.app.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.tuist.app.R
import dev.tuist.app.api.model.AISubscription1
import dev.tuist.app.api.model.ChatGPTSubscriptionLogin1
import dev.tuist.app.ui.noora.NooraSpacing

/** Lists the user's personal Claude and ChatGPT subscriptions. Shown only to users with the `ai` flag. */
@Composable
fun AISubscriptionsSection(
    viewModel: AISubscriptionsViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var subscriptionToDisconnect by remember { mutableStateOf<AISubscription1?>(null) }

    Text(
        text = stringResource(R.string.ai_subscriptions_title),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = NooraSpacing.Spacing4, bottom = NooraSpacing.Spacing3),
    )
    SectionCard {
        if (state.isLoading) {
            Row(Modifier.fillMaxWidth().padding(NooraSpacing.Spacing6), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator(Modifier.size(24.dp))
            }
        }
        state.subscriptions.forEach { subscription ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = NooraSpacing.Spacing6, end = NooraSpacing.Spacing3)
                    .testTag("ai-subscription-${subscription.provider}"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text = providerName(subscription.provider), style = MaterialTheme.typography.bodyLarge)
                Spacer(Modifier.weight(1f))
                when {
                    subscription.connected -> TextButton(onClick = { subscriptionToDisconnect = subscription }) {
                        Text(stringResource(R.string.ai_subscriptions_disconnect), color = MaterialTheme.colorScheme.error)
                    }
                    subscription.loginAvailable -> TextButton(onClick = { viewModel.connect(subscription) }) {
                        Text(stringResource(R.string.ai_subscriptions_connect), color = MaterialTheme.colorScheme.primary)
                    }
                    else -> Text(
                        text = stringResource(R.string.ai_subscriptions_unavailable),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(NooraSpacing.Spacing5),
                    )
                }
            }
        }
    }
    Text(
        text = state.error ?: stringResource(R.string.ai_subscriptions_footer),
        style = MaterialTheme.typography.bodySmall,
        color = if (state.error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = NooraSpacing.Spacing4, vertical = NooraSpacing.Spacing3),
    )

    subscriptionToDisconnect?.let { subscription ->
        AlertDialog(
            onDismissRequest = { subscriptionToDisconnect = null },
            title = { Text(stringResource(R.string.ai_subscriptions_disconnect_title)) },
            text = { Text(stringResource(R.string.ai_subscriptions_disconnect_message, providerName(subscription.provider))) },
            confirmButton = {
                TextButton(onClick = {
                    subscriptionToDisconnect = null
                    viewModel.disconnect(subscription.provider)
                }) {
                    Text(stringResource(R.string.ai_subscriptions_disconnect), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { subscriptionToDisconnect = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    if (state.isConnectingClaude) {
        ClaudeTokenDialog(
            isSaving = state.isSavingClaude,
            error = state.claudeError,
            onConnect = viewModel::saveClaudeToken,
            onDismiss = viewModel::dismissClaude,
        )
    }

    state.chatGPTLogin?.let { login ->
        ChatGPTLoginDialog(
            login = login,
            error = state.chatGPTError
                ?: if (state.isChatGPTLoginExpired) stringResource(R.string.ai_subscriptions_chatgpt_expired) else null,
            onDismiss = viewModel::dismissChatGPT,
        )
    }
}

@Composable
private fun ClaudeTokenDialog(
    isSaving: Boolean,
    error: String?,
    onConnect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    var token by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.ai_subscriptions_claude_title)) },
        text = {
            Column {
                Text(stringResource(R.string.ai_subscriptions_claude_message))
                Spacer(Modifier.height(NooraSpacing.Spacing5))
                OutlinedTextField(
                    value = token,
                    onValueChange = { token = it },
                    label = { Text(stringResource(R.string.ai_subscriptions_claude_token)) },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    // Keeps the keyboard from suggesting or learning the token.
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, autoCorrectEnabled = false),
                    isError = error != null,
                    supportingText = error?.let { { Text(it) } },
                    modifier = Modifier.fillMaxWidth().testTag("claude-token-field"),
                )
            }
        },
        confirmButton = {
            if (isSaving) {
                CircularProgressIndicator(Modifier.size(24.dp))
            } else {
                TextButton(onClick = { onConnect(token) }, enabled = token.isNotBlank()) {
                    Text(stringResource(R.string.ai_subscriptions_connect))
                }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun ChatGPTLoginDialog(
    login: ChatGPTSubscriptionLogin1,
    error: String?,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.ai_subscriptions_chatgpt_title)) },
        text = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = login.userCode,
                    style = MaterialTheme.typography.headlineMedium,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(NooraSpacing.Spacing5))
                Text(
                    text = error ?: stringResource(R.string.ai_subscriptions_chatgpt_message),
                    color = if (error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(NooraSpacing.Spacing3))
                TextButton(onClick = { clipboard.setText(AnnotatedString(login.userCode)) }) {
                    Text(stringResource(R.string.ai_subscriptions_chatgpt_copy))
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(login.verificationUrl))) }) {
                Text(stringResource(R.string.ai_subscriptions_chatgpt_open))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

private fun providerName(provider: String): String = when (provider) {
    "claude" -> "Claude"
    "chatgpt" -> "ChatGPT"
    else -> provider
}
