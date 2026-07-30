package dev.tuist.app.data

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.BuildConfig
import java.net.URI
import java.net.URISyntaxException
import java.util.Locale
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

    val customServerUrl: String?
        get() = prefs.getString(KEY_CUSTOM_SERVER_URL, null)

    val isUsingCustomServerUrl: Boolean get() = customServerUrl != null
    val serverUrl: String get() = customServerUrl ?: current.serverUrl
    val oauthClientId: String get() = current.oauthClientId

    fun setEnvironment(env: TuistEnvironment): Boolean {
        val changed = current != env || customServerUrl != null
        prefs.edit()
            .putString(KEY_ENVIRONMENT, env.name)
            .remove(KEY_CUSTOM_SERVER_URL)
            .apply()
        return changed
    }

    fun setCustomServerUrl(value: String): Boolean {
        val normalizedValue = normalizeServerUrl(value)
        val changed = customServerUrl != normalizedValue
        prefs.edit()
            .putString(KEY_CUSTOM_SERVER_URL, normalizedValue)
            .apply()
        return changed
    }

    fun resetServerUrl(): Boolean {
        val changed = customServerUrl != null
        prefs.edit().remove(KEY_CUSTOM_SERVER_URL).apply()
        return changed
    }

    companion object {
        private const val KEY_ENVIRONMENT = "selected_environment"
        private const val KEY_CUSTOM_SERVER_URL = "custom_server_url"
        private val DEFAULT = TuistEnvironment.PRODUCTION

        fun normalizeServerUrl(value: String): String {
            val trimmedValue = value.trim()
            require(trimmedValue.isNotEmpty()) { "Enter a server address." }

            val valueWithScheme = if (trimmedValue.contains("://")) {
                trimmedValue
            } else {
                "https://$trimmedValue"
            }

            val uri = try {
                URI(valueWithScheme)
            } catch (_: URISyntaxException) {
                throw IllegalArgumentException("$value is not a valid server address.")
            }

            val scheme = uri.scheme?.lowercase(Locale.US)
                ?: throw IllegalArgumentException("$value is not a valid server address.")
            val host = uri.host
                ?.removePrefix("[")
                ?.removeSuffix("]")
                ?.lowercase(Locale.US)
                ?.takeIf { it.isNotEmpty() }
                ?: throw IllegalArgumentException("$value is not a valid server address.")

            require(scheme == "http" || scheme == "https") {
                "$scheme is not supported. Use http or https."
            }
            require(scheme != "http" || isLocalHost(host)) {
                "Use https, or http for a local server."
            }
            require(
                uri.rawUserInfo == null &&
                    (uri.rawPath.isNullOrEmpty() || uri.rawPath == "/") &&
                    uri.rawQuery == null &&
                    uri.rawFragment == null,
            ) {
                "Use the root server address without a path, query, fragment, or credentials."
            }
            require(uri.port == -1 || uri.port in 1..65535) {
                "$value is not a valid server address."
            }

            val port = uri.port.takeUnless {
                it == -1 || (scheme == "http" && it == 80) || (scheme == "https" && it == 443)
            }
            val renderedHost = if (host.contains(':')) "[$host]" else host
            return buildString {
                append(scheme)
                append("://")
                append(renderedHost)
                if (port != null) {
                    append(':')
                    append(port)
                }
            }
        }

        private fun isLocalHost(host: String): Boolean {
            if (host == "localhost" || host == "::1") return true

            val addressComponents = host.split('.')
            return addressComponents.size == 4 &&
                addressComponents.first() == "127" &&
                addressComponents.all { component ->
                    component.toIntOrNull() in 0..255
                }
        }
    }
}
