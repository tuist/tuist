package dev.tuist.app.data.push

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.BuildConfig
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

object FirebaseSetup {
    private val options: FirebaseOptions? by lazy {
        val values = listOf(
            BuildConfig.FIREBASE_APPLICATION_ID,
            BuildConfig.FIREBASE_PROJECT_ID,
            BuildConfig.FIREBASE_API_KEY,
            BuildConfig.FIREBASE_GCM_SENDER_ID,
        )
        if (values.any { it.isBlank() }) return@lazy null
        FirebaseOptions.Builder()
            .setApplicationId(BuildConfig.FIREBASE_APPLICATION_ID)
            .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
            .setApiKey(BuildConfig.FIREBASE_API_KEY)
            .setGcmSenderId(BuildConfig.FIREBASE_GCM_SENDER_ID)
            .build()
    }

    /** Initializes Firebase when this build has a configuration and returns whether FCM is usable. */
    @Synchronized
    fun initialize(context: Context): Boolean {
        val options = options ?: return false
        if (FirebaseApp.getApps(context).isEmpty()) {
            FirebaseApp.initializeApp(context, options)
        }
        return true
    }
}

@Singleton
class PushTokenProvider @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    val isAvailable: Boolean get() = FirebaseSetup.initialize(context)

    suspend fun token(): String = FirebaseMessaging.getInstance().token.await()

    suspend fun reset() {
        if (isAvailable) FirebaseMessaging.getInstance().deleteToken().await()
    }
}
