package dev.tuist.app.data.network

import android.util.Log
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.TuistEnvironment
import dev.tuist.app.data.auth.AuthEvent
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.TokenStorage
import okhttp3.Authenticator
import okhttp3.FormBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import java.io.IOException
import javax.inject.Inject

class TokenRefreshAuthenticator @Inject constructor(
    private val tokenStorage: TokenStorage,
    @PlainClient private val plainClient: OkHttpClient,
    private val environmentConfig: EnvironmentConfig,
    private val authEventBus: AuthEventBus,
) : Authenticator {

    override fun authenticate(route: Route?, response: Response): Request? = synchronized(LOCK) {
        if (response.request.header(HEADER_RETRY_AUTH) != null) return null
        val session = response.request.tag(TokenStorage.Session::class.java) ?: tokenStorage.snapshot()
        val discovery = response.request.tag(ProfileRequest::class.java)
        val (currentToken, savedRefreshToken) = synchronized(tokenStorage) {
            if (!tokenStorage.retryPendingRotation()) throw TokenRefreshException("Could not persist rotated credentials")
            if (discovery != null) {
                val credentials = tokenStorage.credentials(discovery.profileId) ?: return null
                credentials.access to credentials.refresh
            } else {
                if (!tokenStorage.isCurrent(session)) return null
                tokenStorage.getAccessToken() to tokenStorage.getRefreshToken()
            }
        }
        val requestToken = response.request.header("Authorization")?.removePrefix("Bearer ")
        if (currentToken != null && currentToken != requestToken) {
            return response.request.withAccessToken(currentToken)
        }

        val refreshToken = savedRefreshToken ?: run {
            if (currentToken != null) expireSession(session)
            return null
        }

        val origin = session.origin ?: environmentConfig.serverUrl
        val issuingClientId = session.profileId?.let { tokenStorage.credentials(it)?.clientId }
        when (val result = refresh(refreshToken, origin, issuingClientId)) {
            is RefreshResult.Success -> {
                if (!tokenStorage.rotate(session, refreshToken, result.accessToken, result.refreshToken)) return null
                if (discovery == null && !tokenStorage.isCurrent(session)) return null
                response.request.withAccessToken(result.accessToken)
            }
            RefreshResult.Rejected -> {
                if (discovery != null && !tokenStorage.isCurrent(session)) {
                    tokenStorage.removeRejectedProfile(discovery.profileId, refreshToken)
                    return null
                }
                if (!tokenStorage.isCurrent(session)) return null
                if (tokenStorage.getRefreshToken() == refreshToken) {
                    expireSession(session)
                    return null
                }
                val rotatedToken = tokenStorage.getAccessToken() ?: return null
                response.request.withAccessToken(rotatedToken)
            }
            is RefreshResult.Transient -> {
                response.close()
                throw TokenRefreshException(result.message, result.cause)
            }
        }
    }

    private fun refresh(refreshToken: String, origin: String, issuingClientId: String?): RefreshResult {
        val clientId = issuingClientId ?: if (environmentConfig.serverUrl.trimEnd('/') == origin.trimEnd('/')) environmentConfig.oauthClientId
            else TuistEnvironment.entries.firstOrNull { it.serverUrl.trimEnd('/') == origin.trimEnd('/') }?.oauthClientId
                ?: return RefreshResult.Transient("Unknown issuing OAuth client")
        val body = FormBody.Builder()
            .add("grant_type", "refresh_token")
            .add("refresh_token", refreshToken)
            .add("client_id", clientId)
            .build()

        val tokenUrl = origin.toHttpUrl().newBuilder()
            .addPathSegments("oauth2/token")
            .build()

        val request = Request.Builder()
            .url(tokenUrl)
            .post(body)
            .build()

        return try {
            plainClient.newCall(request).execute().use { refreshResponse ->
                val responseBody = refreshResponse.body?.string().orEmpty()
                when {
                    refreshResponse.isSuccessful -> parseTokens(responseBody)
                    refreshResponse.code == 401 ||
                        (refreshResponse.code == 400 && responseBody.oauthError() == "invalid_grant") -> {
                        Log.w(TAG, "Refresh token rejected with status ${refreshResponse.code}")
                        RefreshResult.Rejected
                    }
                    else -> RefreshResult.Transient("Token refresh failed with status ${refreshResponse.code}")
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Token refresh network error", e)
            RefreshResult.Transient("Token refresh network error", e)
        }
    }

    private fun parseTokens(body: String): RefreshResult = try {
        val json = JSONObject(body)
        val accessToken = json.optString("access_token").ifEmpty { null }
        val refreshToken = json.optString("refresh_token").ifEmpty { null }
        if (accessToken != null && refreshToken != null) {
            RefreshResult.Success(accessToken = accessToken, refreshToken = refreshToken)
        } else {
            // The authorization server answers 200 without a token pair when it can no longer mint tokens
            // for the grant's subject, for example once the user has been deleted.
            Log.w(TAG, "Token refresh returned no tokens")
            RefreshResult.Rejected
        }
    } catch (e: Exception) {
        Log.e(TAG, "Token refresh parse error", e)
        RefreshResult.Transient("Token refresh returned an unexpected response", e)
    }

    private fun String.oauthError(): String? = try {
        JSONObject(this).optString("error").ifEmpty { null }
    } catch (_: Exception) {
        null
    }

    private fun Request.withAccessToken(accessToken: String): Request =
        newBuilder()
            .header("Authorization", "Bearer $accessToken")
            .header(HEADER_RETRY_AUTH, "true")
            .build()

    private fun expireSession(session: TokenStorage.Session) {
        try {
            if (!tokenStorage.clearIfCurrent(session, selectFallback = true)) return
        } catch (e: IllegalStateException) {
            throw TokenRefreshException("Could not persist expired session removal", e)
        }
        authEventBus.emit(AuthEvent.SessionExpired)
    }

    private sealed interface RefreshResult {
        data class Success(val accessToken: String, val refreshToken: String) : RefreshResult
        data object Rejected : RefreshResult
        data class Transient(val message: String, val cause: Throwable? = null) : RefreshResult
    }

    companion object {
        private const val TAG = "TokenRefreshAuth"
        private const val HEADER_RETRY_AUTH = "X-Retry-Auth"
        private val LOCK = Any()
    }
}

class TokenRefreshException(message: String, cause: Throwable? = null) : IOException(message, cause)
