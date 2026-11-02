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
import io.mockk.coEvery
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

    private fun NotificationsViewModel.accounts() =
        (uiState.value as NotificationsUiState.Success).content.accounts

    @Test
    fun `loads the accounts' new preview preferences`() = runTest(testDispatcher) {
        val viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(initialAccounts, viewModel.accounts())
        assertEquals("pepicrft", (viewModel.uiState.value as NotificationsUiState.Success).content.personalAccountHandle)
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
    fun `a failed project change is rolled back and reported`() = runTest(testDispatcher) {
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.Off)
        } throws NotificationsError("Project not found")
        val viewModel = createViewModel()
        advanceUntilIdle()
        val error = async { viewModel.errorEvents.first() }

        viewModel.setProjectSetting("tuist", "app", ProjectNotificationSetting.Off)
        advanceUntilIdle()

        assertEquals(initialAccounts, viewModel.accounts())
        assertEquals("Project not found", error.await())
    }

    @Test
    fun `rolling back one change keeps a concurrent change to another account`() = runTest(testDispatcher) {
        val accountResponse = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery { repository.updateNewPreviewAccount("pepicrft", false) } coAnswers { accountResponse.await() }
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.Off)
        } throws NotificationsError("Failed")
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setAccountEnabled("pepicrft", false)
        viewModel.setProjectSetting("tuist", "app", ProjectNotificationSetting.Off)
        advanceUntilIdle()

        assertEquals(initialAccounts.withAccountEnabled("pepicrft", false), viewModel.accounts())
    }

    @Test
    fun `resetting a project sends default and uses the server's preferences`() = runTest(testDispatcher) {
        val serverAccounts = initialAccounts.withProjectSetting("tuist", "cli", ProjectNotificationSetting.Default)
        coEvery {
            repository.updateNewPreviewProject("tuist", "cli", ProjectNotificationSetting.Default)
        } returns serverAccounts
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setProjectSetting("tuist", "cli", ProjectNotificationSetting.Default)
        advanceUntilIdle()

        assertEquals(serverAccounts, viewModel.accounts())
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
