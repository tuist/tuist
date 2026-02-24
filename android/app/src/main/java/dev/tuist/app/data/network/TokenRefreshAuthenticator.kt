package dev.tuist.app.data.network

import android.net.Uri
import android.util.Log
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.auth.AuthEvent
import dev.tuist.app.data.auth.AuthEventBus
import dev.tuist.app.data.auth.TokenStorage
import okhttp3.Authenticator
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import javax.inject.Inject

class TokenRefreshAuthenticator @Inject constructor(
    private val tokenStorage: TokenStorage,
    @PlainClient private val plainClient: OkHttpClient,
    private val environmentConfig: EnvironmentConfig,
    private val authEventBus: AuthEventBus,
) : Authenticator {

    @Synchronized
    override fun authenticate(route: Route?, response: Response): Request? {
        if (response.request.header(HEADER_RETRY_AUTH) != null) return null

        val currentToken = tokenStorage.getAccessToken()
        val requestToken = response.request.header("Authorization")?.removePrefix("Bearer ")
        if (currentToken != null && currentToken != requestToken) {
            return response.request.newBuilder()
                .header("Authorization", "Bearer $currentToken")
                .header(HEADER_RETRY_AUTH, "true")
                .build()
        }

        val refreshToken = tokenStorage.getRefreshToken() ?: run {
            expireSession()
            return null
        }

        val json = JSONObject().apply {
            put("refresh_token", refreshToken)
        }
        val body = json.toString()
            .toRequestBody("application/json".toMediaType())

        val refreshUrl = Uri.parse(environmentConfig.serverUrl).buildUpon()
            .appendEncodedPath("api/auth/refresh_token")
            .build()
            .toString()

        val refreshRequest = Request.Builder()
            .url(refreshUrl)
            .post(body)
            .build()

        val refreshResponse = try {
            plainClient.newCall(refreshRequest).execute()
        } catch (e: Exception) {
            Log.e(TAG, "Token refresh network error", e)
            return null
        }

        if (!refreshResponse.isSuccessful) {
            val errorBody = refreshResponse.body?.string()
            Log.e(TAG, "Token refresh failed with status ${refreshResponse.code}: $errorBody")
            expireSession()
            return null
        }

        val responseBody = refreshResponse.body?.string() ?: run {
            Log.e(TAG, "Token refresh returned empty response body")
            expireSession()
            return null
        }

        return try {
            val responseJson = JSONObject(responseBody)
            val newAccessToken = responseJson.getString("access_token")
            val newRefreshToken = responseJson.getString("refresh_token")
            tokenStorage.storeTokens(newAccessToken, newRefreshToken)

            response.request.newBuilder()
                .header("Authorization", "Bearer $newAccessToken")
                .header(HEADER_RETRY_AUTH, "true")
                .build()
        } catch (e: Exception) {
            Log.e(TAG, "Token refresh parse error", e)
            expireSession()
            null
        }
    }

    private fun expireSession() {
        tokenStorage.clear()
        authEventBus.emit(AuthEvent.SessionExpired)
    }

    companion object {
        private const val TAG = "TokenRefreshAuth"
        private const val HEADER_RETRY_AUTH = "X-Retry-Auth"
    }
}
