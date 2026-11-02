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

    @Before
    fun setUp() {
        api = mockk()
        store = PushInstallationStore(context, EnvironmentConfig(context))
        val tokenProvider = mockk<PushTokenProvider> {
            every { isAvailable } returns true
            coEvery { token() } returns "fcm-token"
        }
        val tokenStorage = mockk<TokenStorage> { every { getAccessToken() } returns "access-token" }
        manager = PushRegistrationManager(context, api, store, tokenProvider, tokenStorage, NetworkModule.provideMoshi())
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
        coEvery { api.registerPushDevice(any(), any()) } returns gone("retired")

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

    private fun gone(reason: String) = Response.error<RegisterPushDevice200Response>(
        410,
        """{"message":"gone","reason":"$reason"}""".toResponseBody(),
    )
}
