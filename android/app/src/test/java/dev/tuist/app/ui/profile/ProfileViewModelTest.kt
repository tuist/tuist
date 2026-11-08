package dev.tuist.app.ui.profile

import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.auth.TokenStorage
import dev.tuist.app.data.featureflags.FeatureFlagsRepository
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.push.PushRegistrationManager
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfileViewModelTest {
    @Test fun `storage error is recoverable and retry clears the UI error`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val session = TokenStorage.Session("alice", 0)
            val auth = mockk<AuthRepository> {
                every { this@mockk.session } returns MutableStateFlow(session)
                every { authState } returns flowOf(AuthState.LoggedIn(Account("alice@example.invalid", "alice")))
                every { signOut(session) } throws IllegalStateException("disk full")
            }
            val flags = mockk<FeatureFlagsRepository> { every { enabled } returns MutableStateFlow(emptySet()) }
            val push = mockk<PushRegistrationManager> {
                coEvery { changeProfile(any()) } coAnswers { firstArg<() -> Unit>().invoke() }
            }
            val model = ProfileViewModel(auth, flags, push)
            model.signOut()
            advanceUntilIdle()
            assertTrue(model.signOutFailed.value)
            every { auth.signOut(session) } returns Unit
            model.signOut()
            advanceUntilIdle()
            assertFalse(model.signOutFailed.value)
        } finally { Dispatchers.resetMain() }
    }
}
