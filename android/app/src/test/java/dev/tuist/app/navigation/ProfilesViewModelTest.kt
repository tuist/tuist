package dev.tuist.app.navigation

import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.auth.TokenStorage
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProfilesViewModelTest {
    @Test fun `switch failure is recoverable by selecting a saved profile again`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val auth = mockk<AuthRepository> {
                every { session } returns MutableStateFlow(TokenStorage.Session("alice", 0))
                coEvery { switchProfile("bob") } throws IllegalStateException("disk full")
            }
            val model = ProfilesViewModel(auth)
            var selected = false
            model.select("bob") { selected = true }
            advanceUntilIdle()
            assertTrue(model.failed.value)
            assertFalse(model.loading.value)
            assertFalse(selected)

            coEvery { auth.switchProfile("bob") } returns Unit
            model.select("bob") { selected = true }
            advanceUntilIdle()
            assertTrue(selected)
            assertFalse(model.failed.value)
            assertFalse(model.loading.value)
            coVerify(exactly = 2) { auth.switchProfile("bob") }
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `dismissing an in flight selection cancels without showing failure or closing a reopened chooser`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val auth = mockk<AuthRepository> {
                every { session } returns MutableStateFlow(TokenStorage.Session("alice", 0))
                coEvery { switchProfile("bob") } coAnswers { awaitCancellation() }
            }
            val model = ProfilesViewModel(auth)
            var selected = false
            model.select("bob") { selected = true }
            runCurrent()
            assertTrue(model.loading.value)
            model.select("alice") { selected = true }
            coVerify(exactly = 0) { auth.switchProfile("alice") }

            model.cancelSelection()
            advanceUntilIdle()
            assertFalse(model.loading.value)
            assertFalse(model.failed.value)
            assertFalse(selected)

            coEvery { auth.switchProfile("bob") } returns Unit
            model.select("bob") { selected = true }
            advanceUntilIdle()
            assertTrue(selected)
        } finally { Dispatchers.resetMain() }
    }
}
