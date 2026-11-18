package dev.tuist.app.data.auth

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.browser.customtabs.CustomTabsClient
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.push.PushRegistrationManager
import io.mockk.coEvery
import io.mockk.mockk
import io.mockk.every
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class AuthRepositoryProfilesTest {
    private val server = MockWebServer()
    private lateinit var tokens: TokenStorage
    private lateinit var auth: AuthRepository
    private lateinit var activity: Activity

    @Before fun setUp() {
        io.mockk.mockkStatic(CustomTabsClient::class)
        every { CustomTabsClient.getPackageName(any(), any()) } returns "fixture.browser"
        every { CustomTabsClient.isEphemeralBrowsingSupported(any(), any()) } returns true
        server.start()
        val prefs = RuntimeEnvironment.getApplication().getSharedPreferences("auth-profiles", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        tokens = TokenStorage(prefs, server.url("/").toString())
        tokens.storeTokens(jwt("alice"), "alice-refresh")
        val environment = mockk<EnvironmentConfig> {
            every { serverUrl } returns server.url("/").toString().trimEnd('/')
            every { oauthClientId } returns "android-client"
        }
        val push = mockk<PushRegistrationManager> {
            coEvery { changeProfile(any()) } coAnswers { firstArg<() -> Unit>().invoke() }
        }
        auth = AuthRepository(tokens, OkHttpClient(), environment, push)
        activity = Robolectric.buildActivity(Activity::class.java).setup().get()
    }

    @After fun tearDown() {
        server.shutdown()
        io.mockk.unmockkStatic(CustomTabsClient::class)
    }

    @Test fun `adding requires cookie isolation and fails closed on an unsupported browser`() {
        every { CustomTabsClient.isEphemeralBrowsingSupported(any(), any()) } returns false
        auth.beginAddProfile()
        auth.startOAuthFlow(activity, "/oauth2/authorize")
        assertNull(shadowOf(activity).nextStartedActivity)
        assertEquals("alice-refresh", tokens.getRefreshToken())
        assertEquals(1, tokens.profiles.value.size)
    }

    @Test fun `failed and malformed add preserve active profile and tokens`() = runBlocking {
        val before = tokens.snapshot()
        auth.beginAddProfile()
        server.enqueue(MockResponse().setResponseCode(500))
        assertTrue(auth.handleOAuthCallback(callback()).isFailure)
        assertEquals(before, tokens.snapshot())
        assertEquals("alice-refresh", tokens.getRefreshToken())
        server.enqueue(MockResponse().setBody("""{"access_token":"malformed","refresh_token":"bob-refresh"}"""))
        assertTrue(auth.handleOAuthCallback(callback()).isFailure)
        assertEquals(before, tokens.snapshot())
        assertEquals(1, tokens.profiles.value.size)
        auth.cancelAddProfile()
        assertFalse(auth.addingProfile.value)
    }

    @Test fun `cancel rejects a late successful token exchange`() = runBlocking {
        auth.beginAddProfile()
        server.enqueue(success().setBodyDelay(300, TimeUnit.MILLISECONDS))
        val uri = callback()
        val pending = async(Dispatchers.IO) { auth.handleOAuthCallback(uri) }
        assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
        auth.cancelAddProfile()
        assertTrue(pending.await().isFailure)
        assertEquals("alice-refresh", tokens.getRefreshToken())
        assertEquals(1, tokens.profiles.value.size)
    }

    @Test fun `successful add keeps both profiles and sign out returns to remaining profile`() = runBlocking {
        val alice = tokens.snapshot().profileId!!
        auth.beginAddProfile()
        server.enqueue(success())
        assertTrue(auth.handleOAuthCallback(callback()).isSuccess)
        assertFalse(auth.addingProfile.value)
        assertEquals(2, tokens.profiles.value.size)
        val bob = tokens.snapshot()
        auth.switchProfile(alice)
        assertEquals("alice-refresh", tokens.getRefreshToken())
        auth.signOut(bob)
        assertEquals(2, tokens.profiles.value.size)
        auth.signOut()
        assertEquals("bob-refresh", tokens.getRefreshToken())
        assertEquals(1, tokens.profiles.value.size)
        auth.signOut()
        assertNull(tokens.getAccessToken())
    }

    @Test fun `cancelled callback coroutine cannot commit credentials after exchange returns`() = runBlocking {
        auth.beginAddProfile()
        server.enqueue(success().setBodyDelay(300, TimeUnit.MILLISECONDS))
        val uri = callback()
        val pending = async(Dispatchers.IO) { auth.handleOAuthCallback(uri) }
        assertNotNull(server.takeRequest(5, TimeUnit.SECONDS))
        pending.cancel()
        pending.join()
        assertEquals("alice-refresh", tokens.getRefreshToken())
        assertEquals(1, tokens.profiles.value.size)
    }

    @Test fun `unsolicited callback and callback after cancel cannot create a profile`() = runBlocking {
        assertTrue(auth.handleOAuthCallback(Uri.parse("tuist://oauth-callback?code=fake&state=fake")).isFailure)
        val uri = callback()
        auth.cancelAddProfile()
        assertTrue(auth.handleOAuthCallback(uri).isFailure)
        assertEquals(0, server.requestCount)
        assertEquals("alice-refresh", tokens.getRefreshToken())
    }

    @Test fun `add login uses selected saved origin and issuing client rather than environment`() = runBlocking {
        val other = MockWebServer()
        other.start()
        try {
            val origin = other.url("/").toString().trimEnd('/')
            tokens.storeTokens(jwt("other-alice"), "other-refresh", origin, "other-client")
            auth.beginAddProfile()
            auth.startOAuthFlow(activity, "/oauth2/authorize")
            val authorize = shadowOf(activity).nextStartedActivity.data!!
            assertEquals(origin, "${authorize.scheme}://${authorize.authority}")
            assertEquals("other-client", authorize.getQueryParameter("client_id"))
            other.enqueue(success())
            val callback = Uri.parse("tuist://oauth-callback?code=fixture-code&state=${authorize.getQueryParameter("state")}")
            assertTrue(auth.handleOAuthCallback(callback).isSuccess)
            val exchange = other.takeRequest(5, TimeUnit.SECONDS)!!
            assertEquals("/oauth2/token", exchange.path)
            assertTrue(exchange.body.readUtf8().contains("client_id=other-client"))
            assertEquals(0, server.requestCount)
            assertEquals(origin, tokens.selectedServer())
            assertEquals("other-client", tokens.credentials(tokens.snapshot().profileId!!)!!.clientId)
            assertEquals(3, tokens.profiles.value.size)
        } finally {
            other.shutdown()
        }
    }

    private fun callback(): Uri {
        auth.startOAuthFlow(activity, "/oauth2/authorize")
        val state = shadowOf(activity).nextStartedActivity.data!!.getQueryParameter("state")
        return Uri.parse("tuist://oauth-callback?code=fixture-code&state=$state")
    }

    private fun success() = MockResponse().setBody("""{"access_token":"${jwt("bob")}","refresh_token":"bob-refresh"}""")
    private fun jwt(subject: String): String {
        val payload = """{"sub":"$subject","email":"$subject@example.invalid","preferred_username":"$subject"}"""
        return "header.${Base64.encodeToString(payload.toByteArray(), Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)}.signature"
    }
}
