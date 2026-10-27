package dev.tuist.app.ui.profile

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil3.compose.SubcomposeAsyncImage
import dev.tuist.app.R
import dev.tuist.app.ui.noora.NooraSpacing
import java.security.MessageDigest

@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel = hiltViewModel(),
) {
    val account by viewModel.account.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showDeleteConfirmation by remember { mutableStateOf(false) }

    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirmation = false },
            title = { Text(stringResource(R.string.delete_account_title)) },
            text = { Text(stringResource(R.string.delete_account_message)) },
            confirmButton = {
                TextButton(onClick = { showDeleteConfirmation = false }) {
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
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = NooraSpacing.Spacing6),
    ) {
            // Avatar section
            account?.let { acct ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = NooraSpacing.Spacing8),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    GravatarAvatar(
                        email = acct.email,
                        displayName = acct.handle,
                        size = 80,
                    )
                    Spacer(Modifier.height(NooraSpacing.Spacing4))
                    Text(
                        text = "@${acct.handle}",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Email section
            account?.let { acct ->
                SectionCard {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(NooraSpacing.Spacing6),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = stringResource(R.string.profile_email),
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            text = acct.email,
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(Modifier.height(NooraSpacing.Spacing5))

            // Links section
            SectionCard {
                LinkRow(
                    title = stringResource(R.string.profile_terms),
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://tuist.dev/terms")))
                    },
                )
                LinkRow(
                    title = stringResource(R.string.profile_privacy),
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://tuist.dev/privacy")))
                    },
                )
            }

            Spacer(Modifier.height(NooraSpacing.Spacing5))

            // Support section
            SectionCard {
                LinkRow(
                    title = stringResource(R.string.profile_get_help),
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("mailto:contact@tuist.dev")))
                    },
                )
            }

            Spacer(Modifier.height(NooraSpacing.Spacing5))

            // App version section
            SectionCard {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(NooraSpacing.Spacing6),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.profile_app_version),
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = "1.0.0",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.height(NooraSpacing.Spacing5))

            // Sign out
            SectionCard {
                TextButton(
                    onClick = { viewModel.signOut() },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = stringResource(R.string.sign_out),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            Spacer(Modifier.height(NooraSpacing.Spacing5))

            // Delete account
            SectionCard {
                TextButton(
                    onClick = { showDeleteConfirmation = true },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        text = stringResource(R.string.profile_delete_account),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            Spacer(Modifier.height(NooraSpacing.Spacing8))
        }
}

@Composable
private fun SectionCard(content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {
        content()
    }
}

@Composable
private fun GravatarAvatar(email: String, displayName: String, size: Int) {
    val gravatarUrl = remember(email) {
        val md5 = MessageDigest.getInstance("MD5")
            .digest(email.trim().lowercase().toByteArray())
            .joinToString("") { "%02x".format(it) }
        "https://www.gravatar.com/avatar/$md5?s=${size * 2}&d=404"
    }
    val shape = RoundedCornerShape(16.dp)

    SubcomposeAsyncImage(
        model = gravatarUrl,
        contentDescription = displayName,
        modifier = Modifier
            .size(size.dp)
            .clip(shape),
        error = {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        MaterialTheme.colorScheme.primaryContainer,
                        shape,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = displayName.take(1).uppercase(),
                    fontSize = (size / 2.5).sp,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        },
    )
}

@Composable
private fun LinkRow(title: String, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Spacer(Modifier.weight(1f))
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
