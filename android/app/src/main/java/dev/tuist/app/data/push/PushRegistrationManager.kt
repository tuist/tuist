package dev.tuist.app.data.push

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.squareup.moshi.Moshi
import dagger.hilt.android.qualifiers.ApplicationContext
import dev.tuist.app.api.PushDevicesApi
import dev.tuist.app.api.model.RegisterPushDevice410Response
import dev.tuist.app.api.model.RegisterPushDeviceRequest
import dev.tuist.app.data.auth.TokenStorage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

sealed interface PushRegistrationResult {
    data object Registered : PushRegistrationResult
    data object Unavailable : PushRegistrationResult
    data object SignedOut : PushRegistrationResult
    data object DisabledOnDevice : PushRegistrationResult
    data object PermissionMissing : PushRegistrationResult
    /** The user removed this device from their device list on another device. */
    data object RemovedByUser : PushRegistrationResult
    data class Failed(val message: String) : PushRegistrationResult
}

@Singleton
class PushRegistrationManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val pushDevicesApi: PushDevicesApi,
    private val store: PushInstallationStore,
    private val tokenProvider: PushTokenProvider,
    private val tokenStorage: TokenStorage,
    private val moshi: Moshi,
) {
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    init {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            tokenStorage.session.map { it.profileId }.distinctUntilChanged().collect {
                mutex.withLock {
                    reconcileOwnerLocked()
                    if (store.needsTokenReset) {
                        withTimeoutOrNull(SIGN_OUT_TIMEOUT_MILLIS) { resetTokenLocked() }
                    }
                }
            }
        }
    }

    // Never call the authenticated push API here: expiry can originate inside that API's authenticator.
    private fun reconcileOwnerLocked() {
        val profile = tokenStorage.snapshot().profileId
        if (profile == null || !store.belongsTo(profile)) {
            store.needsTokenReset = true
            store.clear()
            NotificationManagerCompat.from(context).cancelAll()
        }
        if (profile != null) store.bindProfile(profile)
    }

    private suspend fun resetTokenLocked() {
        try {
            tokenProvider.reset()
            store.needsTokenReset = false
        } catch (e: Exception) {
            Log.w(TAG, "Could not reset the push token", e)
        }
    }

    val isAvailable: Boolean get() = tokenProvider.isAvailable
    val isDeviceEnabled: Boolean get() = tokenStorage.snapshot().profileId?.let {
        store.isDeviceEnabled && store.belongsTo(it) && !store.needsTokenReset
    } ?: false
    val installationId: String? get() = store.installationId

    fun requestSync(force: Boolean = false) {
        scope.launch { sync(force) }
    }

    /**
     * Registers this installation when signed in, enabled, permitted and FCM is configured.
     * Unless [force]d, a registration of the same token is only refreshed once a day; the server
     * retires registrations that are not refreshed for 60 days.
     */
    suspend fun sync(force: Boolean = false): PushRegistrationResult = mutex.withLock {
        reconcileOwnerLocked()
        if (!tokenProvider.isAvailable) return PushRegistrationResult.Unavailable
        if (tokenStorage.getAccessToken() == null) return PushRegistrationResult.SignedOut
        if (!store.isDeviceEnabled) return PushRegistrationResult.DisabledOnDevice
        if (store.needsTokenReset) {
            try {
                tokenProvider.reset()
                store.needsTokenReset = false
            } catch (e: Exception) {
                return PushRegistrationResult.Failed("Could not reset push registration")
            }
        }
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            return PushRegistrationResult.PermissionMissing
        }
        val token = try {
            tokenProvider.token()
        } catch (e: Exception) {
            Log.w(TAG, "Could not obtain an FCM token", e)
            return PushRegistrationResult.Failed(e.message ?: "Could not obtain a push token")
        }
        val now = System.currentTimeMillis()
        val isFresh = store.installationId != null &&
            store.registeredToken == token &&
            now - store.registeredAtMillis < REFRESH_INTERVAL_MILLIS
        if (!force && isFresh) return PushRegistrationResult.Registered
        register(token)
    }

    suspend fun setDeviceEnabled(enabled: Boolean): PushRegistrationResult {
        store.isDeviceEnabled = enabled
        if (enabled) return sync(force = true)
        unregister()
        return PushRegistrationResult.DisabledOnDevice
    }

    /** Best-effort unregistration before sign-out clears credentials; the installation is forgotten either way. */
    suspend fun changeProfile(change: () -> Unit) {
        val original = tokenStorage.snapshot()
        val enabled = store.isDeviceEnabled && original.profileId?.let { store.belongsTo(it) } == true
        try {
            signOut()
            currentCoroutineContext().ensureActive()
            change()
        } finally {
            if (enabled) withContext(NonCancellable) {
                mutex.withLock {
                    if (tokenStorage.isCurrent(original)) {
                        store.bindProfile(original.profileId!!)
                        // Restore intent only, never a retired installation or token.
                        store.isDeviceEnabled = true
                        requestSync(force = true)
                    }
                }
            }
        }
    }

    suspend fun signOut() = mutex.withLock {
        store.needsTokenReset = true
        withTimeoutOrNull(SIGN_OUT_TIMEOUT_MILLIS) {
            unregisterLocked()
            try {
                tokenProvider.reset()
                store.needsTokenReset = false
            } catch (e: Exception) {
                Log.w(TAG, "Could not reset the push token", e)
            }
        }
        store.clear()
        NotificationManagerCompat.from(context).cancelAll()
    }

    /** Notifications are opt-in per account: once signed out, by any path, the next account starts with them off. */
    suspend fun forgetSignedOutState() = mutex.withLock {
        store.needsTokenReset = true
        store.clear()
        NotificationManagerCompat.from(context).cancelAll()
    }

    private suspend fun unregister() = mutex.withLock { unregisterLocked() }

    private suspend fun unregisterLocked() {
        val installationId = store.installationId ?: return
        try {
            pushDevicesApi.unregisterPushDevice(installationId)
        } catch (e: Exception) {
            Log.w(TAG, "Could not unregister the push installation", e)
        }
        store.forgetInstallation()
    }

    private suspend fun register(token: String): PushRegistrationResult {
        var installationId = store.installationId ?: store.rotateInstallationId()
        val request = RegisterPushDeviceRequest(
            environment = RegisterPushDeviceRequest.Environment.production,
            platform = RegisterPushDeviceRequest.Platform.android,
            token = token,
            name = deviceModelName(Build.MANUFACTURER, Build.MODEL),
        )
        for (attempt in 0..1) {
            val response = try {
                pushDevicesApi.registerPushDevice(installationId, request)
            } catch (e: Exception) {
                Log.w(TAG, "Could not register the push installation", e)
                return PushRegistrationResult.Failed(e.message ?: "Could not register this device")
            }
            when {
                response.isSuccessful -> {
                    store.markRegistered(token, System.currentTimeMillis())
                    return PushRegistrationResult.Registered
                }
                // A server that predates push notifications.
                response.code() == 404 -> return PushRegistrationResult.Unavailable
                response.code() == 410 && goneReason(response.errorBody()?.string()) != REASON_RETIRED -> {
                    store.isDeviceEnabled = false
                    store.forgetInstallation()
                    return PushRegistrationResult.RemovedByUser
                }
                // 409: the installation belongs to another user. 410 retired: the ID can't be reused.
                response.code() == 409 || response.code() == 410 -> {
                    if (attempt == 0) installationId = store.rotateInstallationId()
                }
                else -> return PushRegistrationResult.Failed(
                    "This device could not be registered due to an unknown Tuist response of ${response.code()}.",
                )
            }
        }
        return PushRegistrationResult.Failed("This device could not be registered with a new installation ID.")
    }

    private fun goneReason(body: String?): String? = try {
        body?.let { moshi.adapter(RegisterPushDevice410Response::class.java).fromJson(it)?.reason }
    } catch (_: Exception) {
        null
    }

    companion object {
        private const val TAG = "PushRegistration"
        private const val REASON_RETIRED = "retired"
        private val REFRESH_INTERVAL_MILLIS = TimeUnit.DAYS.toMillis(1)
        private const val SIGN_OUT_TIMEOUT_MILLIS = 5_000L
    }
}

/** A readable device model, for example "Google Pixel 9" from manufacturer "Google" and model "Pixel 9". */
fun deviceModelName(manufacturer: String?, model: String?): String? {
    val cleanManufacturer = manufacturer?.trim().orEmpty()
    val cleanModel = model?.trim().orEmpty()
    val name = when {
        cleanModel.isEmpty() -> cleanManufacturer
        cleanManufacturer.isEmpty() || cleanModel.startsWith(cleanManufacturer, ignoreCase = true) -> cleanModel
        else -> "$cleanManufacturer $cleanModel"
    }
    return name.replaceFirstChar { it.titlecase() }.takeIf { it.isNotBlank() }
}
