package dev.tuist.app.data.auth

import android.app.Activity
import android.net.Uri
import android.util.Base64
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import androidx.browser.customtabs.CustomTabsClient
import dev.tuist.app.R
import dev.tuist.app.BuildConfig
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.TuistEnvironment
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.data.network.PlainClient

@Singleton
class AuthRepository @Inject constructor(
    private val tokenStorage: TokenStorage,
    @PlainClient private val okHttpClient: OkHttpClient,
    private val environmentConfig: EnvironmentConfig,
    private val pushRegistrationManager: PushRegistrationManager,
) {
    private data class OAuthAttempt(val verifier: String, val state: String, val origin: String, val clientId: String)
    @Volatile private var pending: OAuthAttempt? = null
    private val authenticating = MutableStateFlow(false)
    @Volatile private var attempt = 0L
    val addingProfile = MutableStateFlow(false)
    val profiles = tokenStorage.profiles
    val session = tokenStorage.session

    fun beginAddProfile() { addingProfile.value = true }

    @Synchronized fun cancelAddProfile() {
        attempt++
        pending = null
        addingProfile.value = false
    }

    suspend fun switchProfile(id: String) {
        cancelAddProfile()
        val originalSession = tokenStorage.snapshot()
        if (session.value.profileId == id) return
        pushRegistrationManager.changeProfile {
            synchronized(this) {
                if (tokenStorage.isCurrent(originalSession)) tokenStorage.switchProfile(id)
            }
        }
    }

    suspend fun selectOrganization(id: String, name: String?) {
        cancelAddProfile()
        val originalSession = tokenStorage.snapshot()
        if (originalSession.profileId == id && originalSession.organization == name) return
        currentCoroutineContext().ensureActive()
        val change = {
            synchronized(this) {
                if (tokenStorage.isCurrent(originalSession)) tokenStorage.selectOrganization(id, name)
            }
        }
        if (originalSession.profileId != id) pushRegistrationManager.changeProfile(change) else change()
    }

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

    @Synchronized fun startOAuthFlow(activity: Activity, path: String) {
        val ephemeral = addingProfile.value
        val browser = if (ephemeral) CustomTabsClient.getPackageName(activity, null) else null
        if (ephemeral && (browser == null || !CustomTabsClient.isEphemeralBrowsingSupported(activity, browser))) {
            android.widget.Toast.makeText(activity, R.string.profiles_browser_required, android.widget.Toast.LENGTH_LONG).show()
            return
        }
        val credentials = if (ephemeral) session.value.profileId?.let { tokenStorage.credentials(it) } else null
        val origin = credentials?.server ?: environmentConfig.serverUrl
        val clientId = credentials?.clientId
            ?: if (origin.trimEnd('/') == environmentConfig.serverUrl.trimEnd('/')) environmentConfig.oauthClientId
            else TuistEnvironment.entries.firstOrNull { it.serverUrl == origin.trimEnd('/') }?.oauthClientId
        if (clientId == null) {
            android.widget.Toast.makeText(activity, R.string.profiles_login_failed, android.widget.Toast.LENGTH_LONG).show()
            return
        }
        attempt++
        val codeVerifier = generateCodeVerifier()
        val codeChallenge = generateCodeChallenge(codeVerifier)
        val state = UUID.randomUUID().toString()
        pending = OAuthAttempt(codeVerifier, state, origin, clientId)

        val uri = Uri.parse("${origin.trimEnd('/')}$path").buildUpon()
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
        val tab = CustomTabsIntent.Builder().setEphemeralBrowsingEnabled(ephemeral).build()
        if (browser != null) tab.intent.setPackage(browser)
        tab.launchUrl(activity, uri)
    }

    suspend fun handleOAuthCallback(uri: Uri): Result<Account> = withContext(Dispatchers.IO) {
        val originalSession = tokenStorage.snapshot()
        val code = uri.getQueryParameter("code")
            ?: return@withContext Result.failure(Exception("Missing authorization code"))
        val (currentAttempt, flow) = synchronized(this@AuthRepository) {
            val flow = pending
            if (flow == null || uri.getQueryParameter("state") != flow.state) {
                return@withContext Result.failure(Exception("OAuth state mismatch"))
            }
            pending = null
            attempt to flow
        }
        authenticating.value = true

        try {
            val body = FormBody.Builder()
                .add("grant_type", "authorization_code")
                .add("code", code)
                .add("redirect_uri", redirectUri)
                .add("client_id", flow.clientId)
                .add("code_verifier", flow.verifier)
                .build()

            val tokenUrl = Uri.parse(flow.origin).buildUpon()
                .appendEncodedPath("oauth2/token")
                .build()
                .toString()

            val request = Request.Builder()
                .url(tokenUrl)
                .post(body)
                .build()

            val responseBody = okHttpClient.newCall(request).execute().use { response ->
                check(response.isSuccessful) { "Token exchange failed with status ${response.code}" }
                response.body?.string() ?: error("Empty response body")
            }

            val json = JSONObject(responseBody)
            val accessToken = json.getString("access_token")
            val refreshToken = json.getString("refresh_token")
            require(refreshToken.isNotBlank()) { "Missing refresh token" }

            val account = JwtParser.parseAccount(accessToken)
                ?: return@withContext Result.failure(Exception("Failed to parse JWT"))

            if (attempt != currentAttempt || !tokenStorage.isCurrent(originalSession)) {
                return@withContext Result.failure(Exception("Sign-in cancelled"))
            }
            currentCoroutineContext().ensureActive()
            pushRegistrationManager.changeProfile {
                synchronized(this@AuthRepository) {
                    check(attempt == currentAttempt && tokenStorage.isCurrent(originalSession)) { "Sign-in cancelled" }
                    tokenStorage.storeTokens(accessToken, refreshToken, flow.origin, flow.clientId)
                    addingProfile.value = false
                }
            }
            Result.success(account)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Result.failure(e)
        } finally {
            authenticating.value = false
        }
    }

    fun signOut() { signOut(tokenStorage.snapshot()) }

    @Synchronized fun signOut(expectedSession: TokenStorage.Session) {
        if (!tokenStorage.isCurrent(expectedSession)) return
        cancelAddProfile()
        tokenStorage.clear(selectFallback = true)
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
