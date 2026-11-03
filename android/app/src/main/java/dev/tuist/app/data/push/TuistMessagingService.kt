package dev.tuist.app.data.push

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import dagger.hilt.android.AndroidEntryPoint
import dev.tuist.app.MainActivity
import dev.tuist.app.R
import javax.inject.Inject

@AndroidEntryPoint
class TuistMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var pushRegistrationManager: PushRegistrationManager

    override fun onNewToken(token: String) {
        pushRegistrationManager.requestSync(force = true)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // A registration that failed to unregister may still receive pushes after the user turned them off.
        if (!pushRegistrationManager.isDeviceEnabled) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val title = message.notification?.title ?: message.data["title"] ?: return
        val body = message.notification?.body ?: message.data["body"]
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(this, NotificationChannels.NEW_PREVIEWS)
            .setSmallIcon(R.drawable.ic_device_mobile)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(this).notify(message.messageId.hashCode(), notification)
    }
}
