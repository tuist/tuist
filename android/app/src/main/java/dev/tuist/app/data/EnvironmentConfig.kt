package dev.tuist.app.data

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

enum class TuistEnvironment(
    val serverUrl: String,
    val oauthClientId: String,
) {
    DEVELOPMENT(
        serverUrl = "http://localhost:8080",
        oauthClientId = "5339abf2-467c-4690-b816-17246ed149d2",
    ),
    STAGING(
        serverUrl = "https://staging.tuist.dev",
        oauthClientId = "bcb85209-0cef-4acd-8dd4-e0d1c5e5e09a",
    ),
    CANARY(
        serverUrl = "https://canary.tuist.dev",
        oauthClientId = "ca49d1d6-acaf-4eaa-b866-774b799044db",
    ),
    PRODUCTION(
        serverUrl = "https://tuist.dev",
        oauthClientId = BuildConfig.OAUTH_CLIENT_ID,
    );

    companion object {
        fun fromName(name: String): TuistEnvironment? =
            entries.find { it.name.equals(name, ignoreCase = true) }
    }
}

@Singleton
class EnvironmentConfig @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("tuist_environment", Context.MODE_PRIVATE)

    val current: TuistEnvironment
        get() {
            if (!BuildConfig.DEBUG) return TuistEnvironment.PRODUCTION
            val name = prefs.getString(KEY_ENVIRONMENT, null) ?: return DEFAULT
            return TuistEnvironment.fromName(name) ?: DEFAULT
        }

    val serverUrl: String get() = current.serverUrl
    val oauthClientId: String get() = current.oauthClientId

    fun setEnvironment(env: TuistEnvironment): Boolean {
        val changed = current != env
        prefs.edit().putString(KEY_ENVIRONMENT, env.name).apply()
        return changed
    }

    companion object {
        private const val KEY_ENVIRONMENT = "selected_environment"
        private val DEFAULT = TuistEnvironment.PRODUCTION
    }
}
