package dev.tuist.app.ui.notifications

import dev.tuist.app.data.push.NotificationRule
import dev.tuist.app.data.push.NotificationsError
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.data.push.ValueMatch
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class NotificationsViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val repository = mockk<NotificationsRepository>()
    private val registration = mockk<PushRegistrationManager>()
    private val betaRule = NotificationRule(id = "rule-1", projects = listOf("tuist/ios-app"), track = ValueMatch.Is("beta"))

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        every { registration.isAvailable } returns true
        every { registration.isDeviceEnabled } returns true
        every { registration.installationId } returns null
        coEvery { repository.listRules() } returns listOf(betaRule)
        coEvery { repository.listDevices() } returns emptyList()
        coEvery { repository.listProjects() } returns listOf("acme/shop", "tuist/ios-app")
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun content(viewModel: NotificationsViewModel) =
        (viewModel.uiState.value as NotificationsUiState.Success).content

    @Test
    fun `a new rule is created and appended with the server id`() = runTest(dispatcher) {
        val draft = NotificationRule(gitBranch = ValueMatch.Contains("release/"))
        coEvery { repository.createRule(draft) } returns draft.copy(id = "rule-2")
        val viewModel = NotificationsViewModel(repository, registration)
        advanceUntilIdle()
        var saved = false

        viewModel.save(draft) { saved = true }
        advanceUntilIdle()

        assertEquals(listOf("rule-1", "rule-2"), content(viewModel).rules.map { it.id })
        assertTrue(saved)
        coVerify(exactly = 0) { repository.updateRule(any()) }
    }

    @Test
    fun `an update adopts what the server saved, and a failed one keeps the rule`() = runTest(dispatcher) {
        // The server normalizes values, so its response wins over the local edit.
        coEvery { repository.updateRule(betaRule.copy(isEnabled = false)) } returns
            betaRule.copy(isEnabled = false, track = ValueMatch.Is("Beta"))
        val viewModel = NotificationsViewModel(repository, registration)
        advanceUntilIdle()

        viewModel.setEnabled(betaRule, false)
        advanceUntilIdle()
        assertEquals(listOf(betaRule.copy(isEnabled = false, track = ValueMatch.Is("Beta"))), content(viewModel).rules)

        val current = content(viewModel).rules.single()
        coEvery { repository.updateRule(any()) } throws IOException("offline")
        viewModel.setEnabled(current, true)
        advanceUntilIdle()
        assertEquals(listOf(current), content(viewModel).rules)
        assertTrue(content(viewModel).rulesInFlight.isEmpty())
    }

    @Test
    fun `condition options merge the rule's projects and skip any-project rules`() = runTest(dispatcher) {
        coEvery { repository.conditionOptions(any(), "tuist/ios-app") } returns mapOf("track" to listOf("beta", "internal"))
        coEvery { repository.conditionOptions(any(), "acme/shop") } returns mapOf("track" to listOf("beta", "qa"))
        val viewModel = NotificationsViewModel(repository, registration)
        advanceUntilIdle()

        val tracks = viewModel.options("track", NotificationRule(projects = listOf("tuist/ios-app", "acme/shop")))

        assertEquals(listOf("beta", "internal", "qa"), tracks)
        assertEquals(emptyList<String>(), viewModel.options("track", NotificationRule()))
    }

    @Test
    fun `servers without rules are unsupported`() = runTest(dispatcher) {
        coEvery { repository.listRules() } throws NotificationsError("Not found", code = 404)
        val viewModel = NotificationsViewModel(repository, registration)
        advanceUntilIdle()

        assertEquals(NotificationsUiState.Unsupported, viewModel.uiState.value)
    }
}
