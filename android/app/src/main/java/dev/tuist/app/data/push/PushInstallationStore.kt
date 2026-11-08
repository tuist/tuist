package dev.tuist.app.data.push

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.data.EnvironmentConfig
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Per-server-environment push installation state. The backing file is excluded from backups
 * (see res/xml/backup_rules.xml) so a restored device never reuses another device's installation ID.
 */
@Singleton
class PushInstallationStore @Inject constructor(
    @ApplicationContext context: Context,
    private val environmentConfig: EnvironmentConfig,
) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun key(name: String) = "${environmentConfig.current.name.lowercase()}.$name"

    val installationId: String? get() = prefs.getString(key(KEY_INSTALLATION_ID), null)

    var isDeviceEnabled: Boolean
        get() = prefs.getBoolean(key(KEY_DEVICE_ENABLED), false)
        set(value) {
            prefs.edit().putBoolean(key(KEY_DEVICE_ENABLED), value).apply()
        }

    val registeredToken: String? get() = prefs.getString(key(KEY_REGISTERED_TOKEN), null)

    val registeredAtMillis: Long get() = prefs.getLong(key(KEY_REGISTERED_AT), 0L)

    /** Replaces the installation ID with a new lowercase UUID and drops the previous registration. */
    fun rotateInstallationId(): String {
        val id = UUID.randomUUID().toString().lowercase()
        prefs.edit()
            .putString(key(KEY_INSTALLATION_ID), id)
            .remove(key(KEY_REGISTERED_TOKEN))
            .remove(key(KEY_REGISTERED_AT))
            .apply()
        return id
    }

    fun markRegistered(token: String, atMillis: Long) {
        prefs.edit()
            .putString(key(KEY_REGISTERED_TOKEN), token)
            .putLong(key(KEY_REGISTERED_AT), atMillis)
            .apply()
    }

    fun forgetInstallation() {
        prefs.edit()
            .remove(key(KEY_INSTALLATION_ID))
            .remove(key(KEY_REGISTERED_TOKEN))
            .remove(key(KEY_REGISTERED_AT))
            .apply()
    }

    fun clear() {
        forgetInstallation()
        prefs.edit().remove(key(KEY_DEVICE_ENABLED)).apply()
    }

    companion object {
        const val PREFS_NAME = "tuist_push"
        private const val KEY_INSTALLATION_ID = "installation_id"
        private const val KEY_DEVICE_ENABLED = "device_enabled"
        private const val KEY_REGISTERED_TOKEN = "registered_token"
        private const val KEY_REGISTERED_AT = "registered_at"
    }
}
