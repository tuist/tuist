package dev.tuist.app.data.featureflags

import android.util.Log
import dev.tuist.app.api.FeatureFlagsApi
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

/** A flag the server turns on per user. [key] is the name the server returns. */
enum class FeatureFlag(val key: String) {
    /** AI features, such as connecting Claude and ChatGPT subscriptions. */
    AI("ai"),
}

/**
 * The feature flags enabled for the signed-in user. Inject it and collect [enabled] to show or hide
 * features; collectors update when a refresh changes the flags. Flags are off until the server turns
 * them on.
 */
@Singleton
class FeatureFlagsRepository @Inject constructor(
    private val featureFlagsApi: FeatureFlagsApi,
) {
    private val _enabled = MutableStateFlow<Set<FeatureFlag>>(emptySet())
    val enabled: StateFlow<Set<FeatureFlag>> = _enabled.asStateFlow()

    /** The account [enabled] belongs to. */
    private var account: Account? = null

    /**
     * Fetches the flags for [state]. Call on launch, when the session changes, and when the app returns
     * to the foreground. Signing out or switching accounts turns every flag off. A failed fetch keeps the
     * account's last flags, so features don't disappear while offline.
     */
    suspend fun refresh(state: AuthState) {
        val loggedIn = state as? AuthState.LoggedIn
        if (loggedIn == null) {
            if (state is AuthState.LoggedOut) {
                account = null
                _enabled.value = emptySet()
            }
            return
        }
        if (account != loggedIn.account) {
            account = loggedIn.account
            _enabled.value = emptySet()
        }
        try {
            val response = featureFlagsApi.listFeatureFlags()
            val body = response.body()
            // The account can change while the request is in flight.
            if (account != loggedIn.account) return
            when {
                response.isSuccessful && body != null ->
                    _enabled.value = FeatureFlag.entries.filter { it.key in body.enabled }.toSet()
                // Servers that predate feature flags enable none.
                response.code() == 404 -> _enabled.value = emptySet()
                else -> Log.w(TAG, "Failed to fetch the feature flags: HTTP ${response.code()}")
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Failed to fetch the feature flags", e)
        }
    }

    companion object {
        private const val TAG = "FeatureFlags"
    }
}
