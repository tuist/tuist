package dev.tuist.app.ui.notifications

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import dev.tuist.app.data.push.NotificationChannels

enum class NotificationPermissionStatus {
    Granted,
    /** The runtime permission can still be requested. */
    NotGranted,
    /** Permanently denied, or notifications/the channel are turned off in system settings. */
    Blocked,
}

class NotificationPermissionState(
    val status: NotificationPermissionStatus,
    val request: () -> Unit,
    val openSettings: () -> Unit,
)

@Composable
fun rememberNotificationPermissionState(onGranted: () -> Unit = {}): NotificationPermissionState {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
    var status by remember { mutableStateOf(notificationPermissionStatus(context, prefs.getBoolean(KEY_REQUESTED, false))) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        prefs.edit().putBoolean(KEY_REQUESTED, true).apply()
        status = notificationPermissionStatus(context, requestedBefore = true)
        if (granted) onGranted()
    }
    LifecycleResumeEffect(Unit) {
        status = notificationPermissionStatus(context, prefs.getBoolean(KEY_REQUESTED, false))
        onPauseOrDispose {}
    }
    return NotificationPermissionState(
        status = status,
        request = {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        },
        openSettings = {
            context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
            )
        },
    )
}

private fun notificationPermissionStatus(context: Context, requestedBefore: Boolean): NotificationPermissionStatus {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
        PackageManager.PERMISSION_GRANTED
    ) {
        val activity = context.findActivity()
        val canAskAgain = !requestedBefore ||
            activity?.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS) == true
        return if (canAskAgain) NotificationPermissionStatus.NotGranted else NotificationPermissionStatus.Blocked
    }
    val manager = NotificationManagerCompat.from(context)
    if (!manager.areNotificationsEnabled()) return NotificationPermissionStatus.Blocked
    val channel = manager.getNotificationChannel(NotificationChannels.NEW_PREVIEWS)
    if (channel?.importance == NotificationManager.IMPORTANCE_NONE) return NotificationPermissionStatus.Blocked
    return NotificationPermissionStatus.Granted
}

private fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

internal const val PREFS_NAME = "tuist_notifications"
private const val KEY_REQUESTED = "permission_requested"
