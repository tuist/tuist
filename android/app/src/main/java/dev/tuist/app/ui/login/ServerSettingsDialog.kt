package dev.tuist.app.ui.login

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import dev.tuist.app.R
import dev.tuist.app.ui.noora.NooraSpacing

@Composable
fun ServerSettingsDialog(
    serverUrl: String,
    isUsingCustomServerUrl: Boolean,
    onSave: (String) -> String?,
    onReset: () -> Unit,
    onDismiss: () -> Unit,
) {
    var serverUrlString by rememberSaveable(serverUrl) { mutableStateOf(serverUrl) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(stringResource(R.string.server_title))
        },
        text = {
            Column {
                OutlinedTextField(
                    value = serverUrlString,
                    onValueChange = {
                        serverUrlString = it
                        errorMessage = null
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.server_address)) },
                    supportingText = {
                        Text(errorMessage ?: stringResource(R.string.server_address_help))
                    },
                    isError = errorMessage != null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    errorMessage = onSave(serverUrlString)
                },
            ) {
                Text(stringResource(R.string.save))
            }
        },
        dismissButton = {
            TextButton(
                onClick = onReset,
                enabled = isUsingCustomServerUrl,
                modifier = Modifier.padding(end = NooraSpacing.Spacing2),
            ) {
                Text(stringResource(R.string.use_default_server))
            }
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.cancel))
            }
        },
    )
}
