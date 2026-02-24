package dev.tuist.app.data.auth

import android.app.Activity
import android.net.Uri
import android.util.Base64
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import dev.tuist.app.BuildConfig
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val tokenStorage: TokenStorage,
    private val okHttpClient: OkHttpClient,
    private val environmentConfig: EnvironmentConfig,
) {
    private var pendingCodeVerifier: String? = null
    private var pendingState: String? = null
    private val authenticating = MutableStateFlow(false)

    private val serverUrl: String get() = environmentConfig.serverUrl
    private val clientId: String get() = environmentConfig.oauthClientId
    private val redirectUri = "tuist://oauth-callback"

    val authState: Flow<AuthState> = combine(
        tokenStorage.accessTokenFlow,
        authenticating,
    ) { token, isAuthenticating ->
        when {
            token != null -> {
                val account = JwtParser.parseAccount(token)
                if (account != null) AuthState.LoggedIn(account) else AuthState.LoggedOut
            }
            isAuthenticating -> AuthState.Authenticating
            else -> AuthState.LoggedOut
        }
    }

    fun startOAuthFlow(activity: Activity, path: String) {
        val codeVerifier = generateCodeVerifier()
        pendingCodeVerifier = codeVerifier
        val codeChallenge = generateCodeChallenge(codeVerifier)
        val state = UUID.randomUUID().toString()
        pendingState = state

        val uri = Uri.parse("$serverUrl$path").buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .build()

        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Starting OAuth flow: $uri")
        }
        CustomTabsIntent.Builder().build().launchUrl(activity, uri)
    }

    suspend fun handleOAuthCallback(uri: Uri): Result<Account> = withContext(Dispatchers.IO) {
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "Handling OAuth callback: $uri")
        }
        authenticating.value = true

        try {
            val returnedState = uri.getQueryParameter("state")
            val expectedState = pendingState
            if (expectedState != null && returnedState != expectedState) {
                return@withContext Result.failure(Exception("OAuth state mismatch").also {
                    Log.e(TAG, "State mismatch: expected=$expectedState returned=$returnedState")
                })
            }

            val code = uri.getQueryParameter("code")
                ?: return@withContext Result.failure(Exception("Missing authorization code").also {
                    Log.e(TAG, "Missing authorization code in callback URI: $uri")
                })

            val codeVerifier = pendingCodeVerifier
                ?: return@withContext Result.failure(Exception("Missing code verifier").also {
                    Log.e(TAG, "Missing code verifier")
                })

            pendingCodeVerifier = null
            pendingState = null

            val body = FormBody.Builder()
                .add("grant_type", "authorization_code")
                .add("code", code)
                .add("redirect_uri", redirectUri)
                .add("client_id", clientId)
                .add("code_verifier", codeVerifier)
                .build()

            val tokenUrl = Uri.parse(serverUrl).buildUpon()
                .appendEncodedPath("oauth2/token")
                .build()
                .toString()

            val request = Request.Builder()
                .url(tokenUrl)
                .post(body)
                .build()

            val response = okHttpClient.newCall(request).execute()

            if (!response.isSuccessful) {
                val errorBody = response.body?.string()
                Log.e(TAG, "Token exchange failed with status ${response.code}: $errorBody")
                return@withContext Result.failure(
                    Exception("Token exchange failed with status ${response.code}")
                )
            }

            val responseBody = response.body?.string()
                ?: return@withContext Result.failure(Exception("Empty response body"))

            val json = JSONObject(responseBody)
            val accessToken = json.getString("access_token")
            val refreshToken = json.getString("refresh_token")

            tokenStorage.storeTokens(accessToken, refreshToken)

            val account = JwtParser.parseAccount(accessToken)
                ?: return@withContext Result.failure(Exception("Failed to parse JWT"))

            Result.success(account)
        } catch (e: Exception) {
            Result.failure(e)
        } finally {
            authenticating.value = false
        }
    }

    fun signOut() {
        tokenStorage.clear()
    }

    companion object {
        private const val TAG = "AuthRepository"
    }

    private fun generateCodeVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(
            bytes,
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
    }

    private fun generateCodeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.encodeToString(
            digest,
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP,
        )
    }
}
