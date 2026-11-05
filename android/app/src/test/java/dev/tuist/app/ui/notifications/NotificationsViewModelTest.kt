package dev.tuist.app.ui.notifications

import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsError
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationPreference
import dev.tuist.app.data.push.ProjectNotificationSetting
import dev.tuist.app.data.push.PushRegistrationManager
import dev.tuist.app.data.push.PushRegistrationResult
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class NotificationsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var repository: NotificationsRepository
    private lateinit var pushRegistrationManager: PushRegistrationManager

    private val initialAccounts = listOf(
        AccountNotificationPreference(
            handle = "tuist",
            enabled = true,
            projects = listOf(
                ProjectNotificationPreference("app", ProjectNotificationSetting.Default, enabled = true),
                ProjectNotificationPreference("cli", ProjectNotificationSetting.On, enabled = true),
            ),
        ),
        AccountNotificationPreference(handle = "pepicrft", enabled = true, projects = emptyList()),
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        repository = mockk {
            coEvery { newPreviewPreferences() } returns initialAccounts
            coEvery { listDevices() } returns emptyList()
        }
        pushRegistrationManager = mockk {
            every { isAvailable } returns true
            every { isDeviceEnabled } returns true
            every { installationId } returns null
        }
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private val authRepository = mockk<AuthRepository> {
        every { authState } returns flowOf(AuthState.LoggedIn(Account(email = "pedro@tuist.dev", handle = "pepicrft")))
    }

    private fun createViewModel() = NotificationsViewModel(repository, pushRegistrationManager, authRepository)

    private fun NotificationsViewModel.content() = (uiState.value as NotificationsUiState.Success).content

    private fun NotificationsViewModel.accounts() = content().accounts

    @Test
    fun `loads the accounts' new preview preferences`() = runTest(testDispatcher) {
        val viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(initialAccounts, viewModel.accounts())
        assertEquals("pepicrft", (viewModel.uiState.value as NotificationsUiState.Success).content.personalAccountHandle)
    }

    @Test
    fun `granting the permission opts this device in`() = runTest(testDispatcher) {
        var enabled = false
        every { pushRegistrationManager.isDeviceEnabled } answers { enabled }
        coEvery { pushRegistrationManager.setDeviceEnabled(true) } coAnswers {
            enabled = true
            PushRegistrationResult.Registered
        }
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.onPermissionGranted()
        advanceUntilIdle()

        coVerify { pushRegistrationManager.setDeviceEnabled(true) }
        assertEquals(true, (viewModel.uiState.value as NotificationsUiState.Success).content.isDeviceEnabled)
    }

    @Test
    fun `turning an account off applies immediately and then uses the server's preferences`() = runTest(testDispatcher) {
        val response = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery { repository.updateNewPreviewAccount("tuist", false) } coAnswers { response.await() }
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAccountEnabled("tuist", false)
        advanceUntilIdle()

        val optimistic = viewModel.accounts().first { it.handle == "tuist" }
        assertEquals(false, optimistic.enabled)
        // Default follows the account; the explicit "on" override keeps the project enabled.
        assertEquals(listOf(false, true), optimistic.projects.map { it.enabled })

        val serverAccounts = initialAccounts.withAccountEnabled("tuist", false) +
            AccountNotificationPreference(handle = "new-org", enabled = true, projects = emptyList())
        response.complete(serverAccounts)
        advanceUntilIdle()

        assertEquals(serverAccounts, viewModel.accounts())
    }

    @Test
    fun `turning a project off overrides the account and uses the server's preferences`() = runTest(testDispatcher) {
        val serverAccounts = initialAccounts.withProjectSetting("tuist", "app", ProjectNotificationSetting.Off)
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.Off)
        } returns serverAccounts
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setProjectEnabled("tuist", "app", false)
        advanceUntilIdle()

        assertEquals(serverAccounts, viewModel.accounts())
    }

    @Test
    fun `a project that matches its account follows it again`() {
        val account = initialAccounts.first { it.handle == "tuist" }

        assertEquals(ProjectNotificationSetting.Default, account.projectSetting(enabled = true))
        assertEquals(ProjectNotificationSetting.Off, account.projectSetting(enabled = false))
        assertEquals(ProjectNotificationSetting.On, account.copy(enabled = false).projectSetting(enabled = true))
    }

    @Test
    fun `a failed change reloads the preferences and reports the error`() = runTest(testDispatcher) {
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.Off)
        } throws NotificationsError("Project not found")
        val viewModel = createViewModel()
        advanceUntilIdle()
        val reloaded = initialAccounts.withAccountEnabled("pepicrft", false)
        coEvery { repository.newPreviewPreferences() } returns reloaded
        val error = async { viewModel.errorEvents.first() }

        viewModel.setProjectEnabled("tuist", "app", false)
        advanceUntilIdle()

        assertEquals(reloaded, viewModel.accounts())
        assertEquals("Project not found", error.await())
    }

    @Test
    fun `overlapping changes reload instead of adopting a stale response`() = runTest(testDispatcher) {
        val accountResponse = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery { repository.updateNewPreviewAccount("tuist", false) } coAnswers { accountResponse.await() }
        // The project's response predates the account change, so adopting it would undo that change.
        coEvery {
            repository.updateNewPreviewProject("tuist", "cli", ProjectNotificationSetting.Off)
        } returns initialAccounts.withProjectSetting("tuist", "cli", ProjectNotificationSetting.Off)
        val viewModel = createViewModel()
        advanceUntilIdle()
        val reloaded = initialAccounts
            .withAccountEnabled("tuist", false)
            .withProjectSetting("tuist", "cli", ProjectNotificationSetting.Default)
        coEvery { repository.newPreviewPreferences() } returns reloaded

        viewModel.setAccountEnabled("tuist", false)
        viewModel.setProjectEnabled("tuist", "cli", false)
        advanceUntilIdle()

        val pending = viewModel.accounts().first { it.handle == "tuist" }
        assertEquals(false, pending.enabled)
        assertEquals(setOf("tuist"), viewModel.content().changesInFlight)

        accountResponse.complete(initialAccounts.withAccountEnabled("tuist", false))
        advanceUntilIdle()

        assertEquals(reloaded, viewModel.accounts())
        assertEquals(emptySet<String>(), viewModel.content().changesInFlight)
    }

    @Test
    fun `a switch ignores another change while its own is in flight`() = runTest(testDispatcher) {
        val response = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery { repository.updateNewPreviewAccount("tuist", any()) } coAnswers { response.await() }
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAccountEnabled("tuist", false)
        viewModel.setAccountEnabled("tuist", true)
        advanceUntilIdle()

        coVerify(exactly = 1) { repository.updateNewPreviewAccount("tuist", any()) }
        assertEquals(false, viewModel.accounts().first { it.handle == "tuist" }.enabled)
        response.complete(initialAccounts.withAccountEnabled("tuist", false))
        advanceUntilIdle()
    }

    @Test
    fun `a server without notifications shows them as unsupported`() = runTest(testDispatcher) {
        coEvery { repository.newPreviewPreferences() } throws NotificationsError("Not found", code = 404)
        val viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(NotificationsUiState.Unsupported, viewModel.uiState.value)
    }

    @Test
    fun `an account summary is custom only when its projects disagree`() {
        val tuist = initialAccounts.first { it.handle == "tuist" }

        assertEquals(AccountNotificationSummary.On, tuist.summary)
        assertEquals(
            AccountNotificationSummary.Custom,
            listOf(tuist).withProjectSetting("tuist", "app", ProjectNotificationSetting.Off).single().summary,
        )
        assertEquals(AccountNotificationSummary.Off, listOf(tuist).withAccountEnabled("tuist", false)
            .withProjectSetting("tuist", "cli", ProjectNotificationSetting.Default).single().summary)
    }

    @Test
    fun `setting a project back to default resolves it from the account`() {
        val accounts = initialAccounts.withAccountEnabled("tuist", false)

        val updated = accounts.withProjectSetting("tuist", "cli", ProjectNotificationSetting.Default)

        val cli = updated.first().projects.first { it.handle == "cli" }
        assertEquals(ProjectNotificationSetting.Default, cli.setting)
        assertEquals(false, cli.enabled)
    }
}
