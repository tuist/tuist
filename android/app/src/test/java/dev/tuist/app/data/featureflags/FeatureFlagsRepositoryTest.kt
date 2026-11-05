package dev.tuist.app.data.featureflags

import dev.tuist.app.api.FeatureFlagsApi
import dev.tuist.app.api.model.FeatureFlags1
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Test
import retrofit2.Response

class FeatureFlagsRepositoryTest {

    private val api: FeatureFlagsApi = mockk()
    private val repository = FeatureFlagsRepository(api)
    private val alice = AuthState.LoggedIn(Account(email = "alice@tuist.dev", handle = "alice"))
    private val bob = AuthState.LoggedIn(Account(email = "bob@tuist.dev", handle = "bob"))

    private fun failure() = Response.error<FeatureFlags1>(500, "".toResponseBody())

    @Test
    fun `enables the flags the server returns and ignores unknown ones`() = runTest {
        coEvery { api.listFeatureFlags() } returns Response.success(FeatureFlags1(listOf("ai", "future-flag")))

        repository.refresh(alice)

        assertEquals(setOf(FeatureFlag.AI), repository.enabled.value)
    }

    @Test
    fun `keeps the account flags when a refresh fails`() = runTest {
        coEvery { api.listFeatureFlags() } returns Response.success(FeatureFlags1(listOf("ai")))
        repository.refresh(alice)

        coEvery { api.listFeatureFlags() } returns failure()
        repository.refresh(alice)

        assertEquals(setOf(FeatureFlag.AI), repository.enabled.value)
    }

    @Test
    fun `turns flags off when the account changes even if the refresh fails`() = runTest {
        coEvery { api.listFeatureFlags() } returns Response.success(FeatureFlags1(listOf("ai")))
        repository.refresh(alice)

        coEvery { api.listFeatureFlags() } returns failure()
        repository.refresh(bob)

        assertEquals(emptySet<FeatureFlag>(), repository.enabled.value)
    }

    @Test
    fun `turns flags off when signing out`() = runTest {
        coEvery { api.listFeatureFlags() } returns Response.success(FeatureFlags1(listOf("ai")))
        repository.refresh(alice)

        repository.refresh(AuthState.LoggedOut)

        assertEquals(emptySet<FeatureFlag>(), repository.enabled.value)
        coVerify(exactly = 1) { api.listFeatureFlags() }
    }
}
