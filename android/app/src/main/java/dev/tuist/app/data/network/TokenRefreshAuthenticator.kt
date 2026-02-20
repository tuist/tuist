package dev.tuist.app.data.network

import android.util.Log
import dev.tuist.app.BuildConfig
import dev.tuist.app.data.auth.TokenStorage
import okhttp3.Authenticator
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import org.json.JSONObject
import javax.inject.Inject

class TokenRefreshAuthenticator @Inject constructor(
    private val tokenStorage: TokenStorage,
    @PlainClient private val plainClient: OkHttpClient,
) : Authenticator {

    override fun authenticate(route: Route?, response: Response): Request? {
        if (response.request.header(HEADER_RETRY_AUTH) != null) return null

        val refreshToken = tokenStorage.getRefreshToken() ?: run {
            tokenStorage.clear()
            return null
        }

        val body = FormBody.Builder()
            .add("grant_type", "refresh_token")
            .add("refresh_token", refreshToken)
            .add("client_id", BuildConfig.OAUTH_CLIENT_ID)
            .build()

        val refreshRequest = Request.Builder()
            .url("${BuildConfig.SERVER_URL}/oauth2/token")
            .post(body)
            .build()

        val refreshResponse = try {
            plainClient.newCall(refreshRequest).execute()
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Token refresh network error", e)
            }
            return null
        }

        if (!refreshResponse.isSuccessful) {
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Token refresh failed with status ${refreshResponse.code}")
            }
            tokenStorage.clear()
            return null
        }

        val responseBody = refreshResponse.body?.string() ?: run {
            tokenStorage.clear()
            return null
        }

        return try {
            val json = JSONObject(responseBody)
            val newAccessToken = json.getString("access_token")
            val newRefreshToken = json.getString("refresh_token")
            tokenStorage.storeTokens(newAccessToken, newRefreshToken)

            response.request.newBuilder()
                .header("Authorization", "Bearer $newAccessToken")
                .header(HEADER_RETRY_AUTH, "true")
                .build()
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) {
                Log.e(TAG, "Token refresh parse error", e)
            }
            tokenStorage.clear()
            null
        }
    }

    companion object {
        private const val TAG = "TokenRefreshAuth"
        private const val HEADER_RETRY_AUTH = "X-Retry-Auth"
    }
}
