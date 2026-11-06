package dev.tuist.atlas

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions

class AtlasApplication : Application() {
    val authentication: AtlasAuthentication by lazy { AtlasAuthentication(this) }

    override fun onCreate() {
        super.onCreate()
        val applicationId = getString(R.string.atlas_firebase_application_id)
        val apiKey = getString(R.string.atlas_firebase_api_key)
        val projectId = getString(R.string.atlas_firebase_project_id)
        val senderId = getString(R.string.atlas_firebase_sender_id)
        if (listOf(applicationId, apiKey, projectId, senderId).any { it.isBlank() }) return
        FirebaseApp.initializeApp(
            this,
            FirebaseOptions
                .Builder()
                .setApplicationId(applicationId)
                .setApiKey(apiKey)
                .setProjectId(projectId)
                .setGcmSenderId(senderId)
                .build(),
        )
    }
}
