package dev.tuist.atlas

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject
import java.util.UUID

// The service never registers devices or refreshes Atlas credentials. Registration is foreground-only.
class AtlasMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = Unit

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (data["schema_version"] != "1" || data["url"].orEmpty().length > 2048) return
        val storage = AtlasSecureStorage(applicationContext)
        val session = runCatching { storage.load("session") }.getOrNull() ?: return
        val origin = session.optJSONObject("registration")?.optString("server")?.takeIf { it.isNotBlank() } ?: return
        val saved = runCatching { storage.load(AtlasPushStorage.key(origin)) }.getOrNull() ?: return
        if (saved.optString("origin") != origin || !saved.optBoolean("enabled") || saved.optString("registration_id").isBlank() ||
            saved.optString("registration_id") != data["registration_id"]
        ) {
            return
        }
        val link = AtlasDestination.parse(data["url"].orEmpty(), AtlasCore().destinations()) ?: return
        if (link.server != AtlasDestination.canonicalServer(saved.optString("origin"))) return
        val manager = getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Atlas notifications", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse(data["url"]))
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val (title, body) = content(data)
        val publicVersion =
            Notification
                .Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle("Atlas")
                .setContentText("You have a new notification.")
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .build()
        val notification =
            Notification
                .Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            manager.notify(data["notification_id"] ?: saved.optString("registration_id"), 1, notification)
        }
    }

    companion object {
        const val CHANNEL = "atlas.notifications"

        // Text is presentation only; the separately validated destination is the sole tap action.
        internal fun content(data: Map<String, String>): Pair<String, String> {
            fun bounded(
                value: String?,
                maximum: Int,
            ): String? {
                if (value == null || value.length > maximum * 2) return null
                val text = value.trim()
                if (text.isEmpty() || text.codePointCount(0, text.length) > maximum) return null
                if (text.codePoints().anyMatch {
                        Character.isISOControl(it) || it in 0x202A..0x202E || it in 0x2066..0x2069 ||
                            it == 0x200E || it == 0x200F || it == 0x061C ||
                            Character.getType(it) == Character.SURROGATE.toInt()
                    }
                ) {
                    return null
                }
                return text
            }
            val title = bounded(data["title"], 80)
            val body = bounded(data["body"], 320)
            return if (title != null && body != null) title to body else "Atlas" to "You have a new notification."
        }
    }
}

class AtlasPushNotifications(
    context: Context,
    private val authentication: AtlasAuthentication,
) {
    private val context = context.applicationContext
    private val storage = AtlasSecureStorage(this.context)
    private val main = Handler(Looper.getMainLooper())
    var listener: (() -> Unit)? = null
    var enabled = false
        private set
    var busy = false
        private set
    var message: String? = null
        private set
    private var server: String? = null
    private var lastSync = 0L
    private var afterSync: (() -> Unit)? = null
    private var generation = 0
    val available: Boolean get() = FirebaseApp.getApps(context).isNotEmpty()

    fun configure(server: String?) {
        if (this.server == server) return
        this.server = server
        enabled = false
        lastSync = 0
        message = null
        val saved = server?.let { origin -> runCatching { storage.load(AtlasPushStorage.key(origin)) }.getOrNull() }
        if (server != null && saved?.optString("origin") == server) {
            enabled = saved.optBoolean("enabled")
            if (!enabled) disable() else refresh()
        }
    }

    fun enable() {
        if (busy || server == null) return
        if (!available) {
            message = "Push notifications are not configured in this build."
            listener?.invoke()
            return
        }
        if (!context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            message = "Allow Atlas notifications in Android Settings to enable alerts."
            listener?.invoke()
            return
        }
        val origin = server ?: return
        val saved = runCatching { storage.load(AtlasPushStorage.key(origin)) }.getOrNull()
        if (saved != null) {
            message = "Finish disabling the previous notification registration before enabling again."
            disable()
            return
        }
        try {
            storage.save(
                AtlasPushStorage.key(origin),
                JSONObject().put("installation_id", UUID.randomUUID().toString()).put("origin", origin).put("enabled", true),
            )
            enabled = true
            refresh(force = true)
        } catch (_: Exception) {
            message = "Could not securely save notification settings."
            listener?.invoke()
        }
    }

    fun refresh(force: Boolean = false) {
        if (!enabled || busy || !available || (!force && System.currentTimeMillis() - lastSync < 300_000)) return
        if (!context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            disable()
            return
        }
        val origin = server ?: return
        val saved = runCatching { storage.load(AtlasPushStorage.key(origin)) }.getOrNull() ?: return
        if (saved.optString("origin") != origin || !saved.optBoolean("enabled")) return
        busy = true
        val attempt = ++generation
        val timeout =
            Runnable {
                if (busy && generation == attempt) {
                    message = "Obtaining a push token timed out. Try again when connected."
                    finish()
                }
            }
        main.postDelayed(timeout, 15_000)
        listener?.invoke()
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            main.post {
                main.removeCallbacks(timeout)
                if (generation != attempt) return@post
                if (!task.isSuccessful || server != origin || !enabled) {
                    message = "Could not obtain a push token. Google Play services and a configured Firebase project are required."
                    finish()
                    return@post
                }
                authentication.push(
                    JSONObject()
                        .put("action", "register")
                        .put("installation_id", saved.getString("installation_id"))
                        .put("platform", "android")
                        .put("environment", "production")
                        .put("token", task.result),
                ) { result ->
                    if (server == origin && enabled) {
                        result.fold(
                            onSuccess = { response ->
                                saved.put("registration_id", response.optString("registration_id"))
                                runCatching { storage.save(AtlasPushStorage.key(origin), saved) }
                                    .onFailure { message = "Could not securely save notification registration." }
                                    .onSuccess {
                                        message = null
                                        lastSync = System.currentTimeMillis()
                                    }
                            },
                            onFailure = { failure ->
                                if ((failure as? AuthFailure)?.kind == "conflict") {
                                    disable { enable() }
                                } else {
                                    message = "Could not sync notifications. Atlas will retry when you return."
                                }
                            },
                        )
                    }
                    finish()
                }
            }
        }
    }

    fun disable(completion: () -> Unit = {}) {
        enabled = false
        context.getSystemService(NotificationManager::class.java).cancelAll()
        if (busy) {
            afterSync = { disable(completion) }
            return
        }
        val origin = server
        val saved = origin?.let { runCatching { storage.load(AtlasPushStorage.key(it)) }.getOrNull() }
        if (saved == null || origin == null) {
            completion()
            return
        }
        try {
            saved.put("enabled", false)
            storage.save(AtlasPushStorage.key(origin), saved)
        } catch (_: Exception) {
            message = "Could not securely disable notifications. Try again before signing out."
            listener?.invoke()
            completion()
            return
        }
        if (saved.optString("origin") != server || authentication.server == null) {
            completion()
            return
        }
        busy = true
        authentication.push(JSONObject().put("action", "unregister").put("installation_id", saved.getString("installation_id"))) { result ->
            result.fold(
                onSuccess = {
                    runCatching { storage.delete(AtlasPushStorage.key(origin)) }
                    message = null
                },
                onFailure = { message = "Notifications are off locally. Server cleanup will retry at your next sign-in." },
            )
            finish()
            completion()
        }
    }

    private fun finish() {
        generation += 1
        busy = false
        listener?.invoke()
        val pending = afterSync
        afterSync = null
        pending?.invoke()
    }
}
