package dev.tuist.app.ui.notifications

import dev.tuist.app.data.push.AccountNotificationPreference
import dev.tuist.app.data.push.NotificationsError
import dev.tuist.app.data.push.NotificationsRepository
import dev.tuist.app.data.push.ProjectNotificationPreference
import dev.tuist.app.data.push.ProjectNotificationSetting
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProjectNotificationsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var repository: NotificationsRepository

    private val initialAccounts = listOf(
        AccountNotificationPreference(
            handle = "tuist",
            enabled = false,
            projects = listOf(ProjectNotificationPreference("app", ProjectNotificationSetting.Default, enabled = false)),
        ),
    )

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        repository = mockk { coEvery { newPreviewPreferences() } returns initialAccounts }
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel() = ProjectNotificationsViewModel(repository).also { it.load() }

    @Test
    fun `finds a project by its full handle`() {
        val (account, project) = initialAccounts.findProject("tuist/app")!!

        assertEquals("tuist", account.handle)
        assertEquals("app", project.handle)
        assertNull(initialAccounts.findProject("tuist/unknown"))
        assertNull(initialAccounts.findProject("other/app"))
        assertNull(initialAccounts.findProject("tuist"))
    }

    @Test
    fun `a change applies immediately and then uses the server's preferences`() = runTest(testDispatcher) {
        val response = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.On)
        } coAnswers { response.await() }
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setSetting("tuist/app", ProjectNotificationSetting.On)
        advanceUntilIdle()

        val optimistic = viewModel.accounts.value.findProject("tuist/app")!!.second
        assertEquals(ProjectNotificationPreference("app", ProjectNotificationSetting.On, enabled = true), optimistic)

        val serverAccounts = initialAccounts.withProjectSetting("tuist", "app", ProjectNotificationSetting.On) +
            AccountNotificationPreference(handle = "new-org", enabled = true, projects = emptyList())
        response.complete(serverAccounts)
        advanceUntilIdle()

        assertEquals(serverAccounts, viewModel.accounts.value)
    }

    @Test
    fun `a failed change is rolled back and reported`() = runTest(testDispatcher) {
        coEvery {
            repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.Off)
        } throws NotificationsError("Project not found")
        val viewModel = createViewModel()
        advanceUntilIdle()
        val error = async { viewModel.errorEvents.first() }

        viewModel.setSetting("tuist/app", ProjectNotificationSetting.Off)
        advanceUntilIdle()

        assertEquals(initialAccounts, viewModel.accounts.value)
        assertEquals("Project not found", error.await())
    }

    @Test
    fun `ignores changes to projects missing from the preferences`() = runTest(testDispatcher) {
        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.setSetting("tuist/unknown", ProjectNotificationSetting.On)
        advanceUntilIdle()

        coVerify(exactly = 0) { repository.updateNewPreviewProject(any(), any(), any()) }
    }

    @Test
    fun `a refresh in flight does not overwrite a change`() = runTest(testDispatcher) {
        val viewModel = createViewModel()
        advanceUntilIdle()
        val staleRefresh = CompletableDeferred<List<AccountNotificationPreference>>()
        coEvery { repository.newPreviewPreferences() } coAnswers { staleRefresh.await() }
        val saved = initialAccounts.withProjectSetting("tuist", "app", ProjectNotificationSetting.On)
        coEvery { repository.updateNewPreviewProject("tuist", "app", ProjectNotificationSetting.On) } returns saved

        viewModel.load()
        advanceUntilIdle()
        viewModel.setSetting("tuist/app", ProjectNotificationSetting.On)
        staleRefresh.complete(initialAccounts)
        advanceUntilIdle()

        assertEquals(saved, viewModel.accounts.value)
    }
}
