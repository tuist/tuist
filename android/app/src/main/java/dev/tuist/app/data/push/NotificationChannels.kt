package dev.tuist.app.data.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import dev.tuist.app.R

object NotificationChannels {
    const val NEW_PREVIEWS = "new_previews"

    fun create(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            NEW_PREVIEWS,
            context.getString(R.string.notifications_channel_new_previews),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.notifications_channel_new_previews_description)
        }
        manager.createNotificationChannel(channel)
    }
}
