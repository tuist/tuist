package dev.tuist.app.data.push

import android.content.Context
import dev.tuist.app.api.PushDevicesApi
import dev.tuist.app.api.model.RegisterPushDevice200Response
import dev.tuist.app.data.EnvironmentConfig
import dev.tuist.app.data.TuistEnvironment
import dev.tuist.app.data.auth.TokenStorage
import dev.tuist.app.data.network.NetworkModule
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import retrofit2.Response

@RunWith(RobolectricTestRunner::class)
class PushRegistrationManagerTest {

    private val context: Context = RuntimeEnvironment.getApplication()
    private lateinit var api: PushDevicesApi
    private lateinit var store: PushInstallationStore
    private lateinit var manager: PushRegistrationManager
    private lateinit var tokenProvider: PushTokenProvider
    private lateinit var tokenStorage: TokenStorage

    @Before
    fun setUp() {
        api = mockk()
        store = PushInstallationStore(context, EnvironmentConfig(context))
        tokenProvider = mockk<PushTokenProvider> {
            every { isAvailable } returns true
            coEvery { token() } returns "fcm-token"
            coEvery { reset() } returns Unit
        }
        tokenStorage = mockk<TokenStorage> {
            every { getAccessToken() } returns "access-token"
            every { session } returns kotlinx.coroutines.flow.MutableStateFlow(TokenStorage.Session("profile", 0))
            every { snapshot() } returns TokenStorage.Session("profile", 0)
            every { isCurrent(any()) } answers { firstArg<TokenStorage.Session>() == TokenStorage.Session("profile", 0) }
        }
        manager = PushRegistrationManager(context, api, store, tokenProvider, tokenStorage, NetworkModule.provideMoshi())
        store.isDeviceEnabled = true
    }

    @Test fun `automatic fallback inside push transport cancels delivered notifications and retires outgoing token without recursion`() = runTest {
        val server = okhttp3.mockwebserver.MockWebServer()
        server.start()
        try {
            val prefs = context.getSharedPreferences("push-expiry", Context.MODE_PRIVATE)
            prefs.edit().clear().commit()
            val tokens = TokenStorage(prefs, server.url("/").toString())
            tokens.storeTokens("bob", "bob-refresh")
            val bob = tokens.snapshot().profileId!!
            tokens.storeTokens("alice", "alice-refresh")
            val alice = tokens.snapshot().profileId!!
            store.clear()
            store.bindProfile(alice)
            store.isDeviceEnabled = true
            store.needsTokenReset = false
            val retired = store.rotateInstallationId()
            val notifications = context.getSystemService(android.app.NotificationManager::class.java)
            notifications.createNotificationChannel(android.app.NotificationChannel("expiry", "Expiry", android.app.NotificationManager.IMPORTANCE_DEFAULT))
            notifications.notify(42, android.app.Notification.Builder(context, "expiry").setSmallIcon(android.R.drawable.ic_dialog_info).build())
            assertEquals(1, notifications.activeNotifications.size)
            val environment = mockk<EnvironmentConfig> {
                every { serverUrl } returns server.url("/").toString()
                every { oauthClientId } returns "android-client"
            }
            val client = okhttp3.OkHttpClient.Builder()
                .addInterceptor(dev.tuist.app.data.network.AuthInterceptor(tokens))
                .addNetworkInterceptor(dev.tuist.app.data.network.SessionGuardInterceptor(tokens))
                .authenticator(dev.tuist.app.data.network.TokenRefreshAuthenticator(tokens, okhttp3.OkHttpClient(), environment, dev.tuist.app.data.auth.AuthEventBus()))
                .build()
            server.enqueue(okhttp3.mockwebserver.MockResponse().setResponseCode(401))
            server.enqueue(okhttp3.mockwebserver.MockResponse().setResponseCode(400).setBody("""{"error":"invalid_grant"}"""))
            coEvery { api.registerPushDevice(retired, any()) } answers {
                client.newCall(okhttp3.Request.Builder().url(server.url("/push/devices")).build()).execute().close()
                registered()
            }
            val reset = java.util.concurrent.CountDownLatch(1)
            coEvery { tokenProvider.reset() } answers {
                reset.countDown()
                throw java.io.IOException("FCM offline")
            }
            val automatic = PushRegistrationManager(context, api, store, tokenProvider, tokens, NetworkModule.provideMoshi())
            assertTrue(automatic.sync(force = true) is PushRegistrationResult.Failed)
            assertTrue(reset.await(5, java.util.concurrent.TimeUnit.SECONDS))
            assertEquals(PushRegistrationResult.DisabledOnDevice, automatic.sync())
            assertEquals(bob, tokens.snapshot().profileId)
            assertEquals(0, notifications.activeNotifications.size)
            assertNull(store.installationId)
            assertNull(store.registeredToken)
            assertTrue(store.needsTokenReset)
            assertFalse(automatic.isDeviceEnabled)
            coVerify(exactly = 0) { api.unregisterPushDevice(any()) }
            assertTrue(automatic.setDeviceEnabled(true) is PushRegistrationResult.Failed)
            coEvery { tokenProvider.reset() } returns Unit
            coEvery { api.registerPushDevice(any(), any()) } returns registered()
            assertEquals(PushRegistrationResult.Registered, automatic.sync())
            assertFalse(store.needsTokenReset)
            assertNotEquals(retired, store.installationId)
        } finally { server.shutdown() }
    }

    @Test fun `failed profile change restores opt in but never reuses retired installation`() = runTest {
        every { tokenProvider.isAvailable } returns false
        store.bindProfile("profile")
        val retired = store.rotateInstallationId()
        coEvery { api.unregisterPushDevice(retired) } returns Response.success(Unit)
        try {
            manager.changeProfile { error("credential commit failed") }
            throw AssertionError("Expected failure")
        } catch (_: IllegalStateException) { }
        assertTrue(store.isDeviceEnabled)
        assertTrue(store.belongsTo("profile"))
        assertNull(store.installationId)
        assertNull(store.registeredToken)
    }

    @Test fun `cancelled profile change restores opt in with reset still required`() = runTest {
        every { tokenProvider.isAvailable } returns false
        store.bindProfile("profile")
        store.forgetInstallation()
        coEvery { tokenProvider.reset() } throws kotlinx.coroutines.CancellationException("cancel")
        try {
            manager.changeProfile { throw kotlinx.coroutines.CancellationException("cancel") }
        } catch (_: kotlinx.coroutines.CancellationException) { }
        assertTrue(store.isDeviceEnabled)
        assertTrue(store.needsTokenReset)
        assertNull(store.installationId)
    }

    @Test fun `successful profile change does not transfer outgoing notification opt in`() = runTest {
        every { tokenProvider.isAvailable } returns false
        store.bindProfile("profile")
        store.forgetInstallation()
        manager.changeProfile {
            every { tokenStorage.isCurrent(any()) } returns false
            every { tokenStorage.snapshot() } returns TokenStorage.Session("bob", 1)
        }
        assertFalse(store.isDeviceEnabled)
        assertFalse(manager.isDeviceEnabled)
    }

    @Test
    fun `does not register until the user opts in, and signing out forgets the opt-in`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns registered()
        manager.forgetSignedOutState()

        assertEquals(PushRegistrationResult.DisabledOnDevice, manager.sync(force = true))
        coVerify(exactly = 0) { api.registerPushDevice(any(), any()) }

        assertEquals(PushRegistrationResult.Registered, manager.setDeviceEnabled(true))
        manager.forgetSignedOutState()

        assertFalse(manager.isDeviceEnabled)
        assertNull(manager.installationId)
    }

    @Test
    fun `registers with a new lowercase installation ID`() = runTest {
        val ids = mutableListOf<String>()
        coEvery { api.registerPushDevice(capture(ids), any()) } returns registered()

        val result = manager.sync()

        assertEquals(PushRegistrationResult.Registered, result)
        assertEquals(ids.single(), store.installationId)
        assertEquals(ids.single().lowercase(), ids.single())
        assertEquals("fcm-token", store.registeredToken)
    }

    @Test
    fun `does not re-register a fresh registration unless forced`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns registered()

        manager.sync()
        manager.sync()
        coVerify(exactly = 1) { api.registerPushDevice(any(), any()) }

        manager.sync(force = true)
        coVerify(exactly = 2) { api.registerPushDevice(any(), any()) }
    }

    @Test
    fun `rotates the installation ID and retries once when it was retired`() = runTest {
        val ids = mutableListOf<String>()
        coEvery { api.registerPushDevice(capture(ids), any()) } returnsMany listOf(
            gone("retired"),
            registered(),
        )

        val result = manager.sync()

        assertEquals(PushRegistrationResult.Registered, result)
        assertEquals(2, ids.size)
        assertNotEquals(ids[0], ids[1])
        assertEquals(ids[1], store.installationId)
        assertTrue(store.isDeviceEnabled)
    }

    @Test
    fun `rotates the installation ID and retries once when it belongs to another user`() = runTest {
        val ids = mutableListOf<String>()
        coEvery { api.registerPushDevice(capture(ids), any()) } returnsMany listOf(
            Response.error(409, """{"message":"conflict"}""".toResponseBody()),
            registered(),
        )

        assertEquals(PushRegistrationResult.Registered, manager.sync())
        assertNotEquals(ids[0], ids[1])
        assertEquals(ids[1], store.installationId)
    }

    @Test
    fun `fails without retrying again when the rotated ID is rejected too`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } answers { gone("retired") }

        val result = manager.sync()

        assertTrue(result is PushRegistrationResult.Failed)
        coVerify(exactly = 2) { api.registerPushDevice(any(), any()) }
    }

    @Test
    fun `turns notifications off and stops registering when the user removed the device`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns gone("removed")

        val result = manager.sync(force = true)

        assertEquals(PushRegistrationResult.RemovedByUser, result)
        assertFalse(store.isDeviceEnabled)
        assertNull(store.installationId)
        assertEquals(PushRegistrationResult.DisabledOnDevice, manager.sync(force = true))
        coVerify(exactly = 1) { api.registerPushDevice(any(), any()) }
    }

    @Test
    fun `treats an unknown gone reason as removed`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns gone("archived")

        assertEquals(PushRegistrationResult.RemovedByUser, manager.sync())
        assertFalse(store.isDeviceEnabled)
        coVerify(exactly = 1) { api.registerPushDevice(any(), any()) }
    }

    @Test
    fun `reports a server without push support as unavailable without retrying`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns
            Response.error(404, """{"message":"not found"}""".toResponseBody())

        assertEquals(PushRegistrationResult.Unavailable, manager.sync())
        assertTrue(store.isDeviceEnabled)
        coVerify(exactly = 1) { api.registerPushDevice(any(), any()) }
    }

    @Test
    fun `re-enabling after removal registers with a new installation ID`() = runTest {
        val ids = mutableListOf<String>()
        coEvery { api.registerPushDevice(capture(ids), any()) } returnsMany listOf(
            gone("removed"),
            registered(),
        )
        manager.sync()

        val result = manager.setDeviceEnabled(true)

        assertEquals(PushRegistrationResult.Registered, result)
        assertNotEquals(ids[0], ids[1])
        assertTrue(store.isDeviceEnabled)
    }

    @Test
    fun `sign out unregisters and forgets the installation`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns registered()
        coEvery { api.unregisterPushDevice(any()) } returns Response.success(204, Unit)
        manager.sync()
        val installationId = store.installationId!!

        manager.signOut()

        coVerify { api.unregisterPushDevice(installationId) }
        assertNull(store.installationId)
    }

    @Test
    fun `installation IDs are stored per server environment`() = runTest {
        coEvery { api.registerPushDevice(any(), any()) } returns registered()
        manager.sync()
        val productionId = store.installationId

        EnvironmentConfig(context).setEnvironment(TuistEnvironment.STAGING)

        assertNull(store.installationId)
        EnvironmentConfig(context).setEnvironment(TuistEnvironment.PRODUCTION)
        assertEquals(productionId, store.installationId)
    }

    private fun registered() = Response.success(RegisterPushDevice200Response(registrationId = "registration"))

    @Test fun `changing login owner drops old opt-in and installation`() {
        store.bindProfile("alice")
        store.isDeviceEnabled = true
        store.rotateInstallationId()
        store.markRegistered("alice-fcm", 123)
        store.bindProfile("bob")
        assertFalse(store.isDeviceEnabled)
        assertNull(store.installationId)
        assertNull(store.registeredToken)
    }

    @Test fun `failed token retirement blocks registration for the next login until retry succeeds`() = runTest {
        coEvery { tokenProvider.reset() } throws java.io.IOException("offline")
        manager.signOut()
        assertTrue(store.needsTokenReset)
        assertTrue(manager.setDeviceEnabled(true) is PushRegistrationResult.Failed)
        coVerify(exactly = 0) { api.registerPushDevice(any(), any()) }
        coEvery { tokenProvider.reset() } returns Unit
        coEvery { api.registerPushDevice(any(), any()) } returns registered()
        assertEquals(PushRegistrationResult.Registered, manager.sync())
        assertFalse(store.needsTokenReset)
    }

    private fun gone(reason: String) = Response.error<RegisterPushDevice200Response>(
        410,
        """{"message":"gone","reason":"$reason"}""".toResponseBody(),
    )
}
