package dev.tuist.app.ui.previews

import android.content.Context
import android.content.SharedPreferences
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.Project
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.previews.PreviewsPage
import dev.tuist.app.data.previews.PreviewsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PreviewsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var previewsRepository: PreviewsRepository
    private lateinit var authRepository: AuthRepository
    private lateinit var context: Context

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        previewsRepository = mockk()
        authRepository = mockk()
        val editor = mockk<SharedPreferences.Editor>(relaxed = true)
        val prefs = mockk<SharedPreferences> {
            every { getString(any(), any()) } returns null
            every { edit() } returns editor
        }
        context = mockk {
            every { getSharedPreferences(any(), any()) } returns prefs
        }
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): PreviewsViewModel {
        return PreviewsViewModel(previewsRepository, authRepository, context)
    }

    @Test
    fun `loads projects and previews after auth state becomes LoggedIn`() = runTest(testDispatcher) {
        val projects = listOf(createProject(1, "tuist/tuist"))
        val previews = listOf(createPreview("1", "App Preview"))
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns projects
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 1) } returns PreviewsPage(
            previews = previews,
            currentPage = 1,
            hasNextPage = false,
        )

        val viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is PreviewsUiState.Success)
        val success = state as PreviewsUiState.Success
        assertEquals(projects, success.projects)
        assertEquals(projects.first(), success.selectedProject)
        assertEquals(previews, success.previews)
        assertFalse(success.hasMorePreviews)
    }

    @Test
    fun `shows empty state when no projects found`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns emptyList()

        val viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is PreviewsUiState.Empty)
        assertEquals("no_projects", (state as PreviewsUiState.Empty).message)
    }

    @Test
    fun `sets Error state when loading projects fails`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } throws RuntimeException("Network error")

        val viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is PreviewsUiState.Error)
        assertEquals("Network error", (state as PreviewsUiState.Error).message)
    }

    @Test
    fun `selectProject loads previews for new project`() = runTest(testDispatcher) {
        val project1 = createProject(1, "tuist/tuist")
        val project2 = createProject(2, "tuist/cloud")
        val projects = listOf(project1, project2)
        val previews1 = listOf(createPreview("1", "Preview 1"))
        val previews2 = listOf(createPreview("2", "Preview 2"))

        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns projects
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 1) } returns PreviewsPage(previews1, 1, false)
        coEvery { previewsRepository.listPreviews("tuist", "cloud", page = 1) } returns PreviewsPage(previews2, 1, false)

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.selectProject(project2)
        advanceUntilIdle()

        val state = viewModel.uiState.value as PreviewsUiState.Success
        assertEquals(project2, state.selectedProject)
        assertEquals(previews2, state.previews)
    }

    @Test
    fun `loadMorePreviews appends next page`() = runTest(testDispatcher) {
        val projects = listOf(createProject(1, "tuist/tuist"))
        val page1Previews = listOf(createPreview("1", "Preview 1"))
        val page2Previews = listOf(createPreview("2", "Preview 2"))

        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns projects
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 1) } returns PreviewsPage(page1Previews, 1, true)
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 2) } returns PreviewsPage(page2Previews, 2, false)

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.loadMorePreviews()
        advanceUntilIdle()

        val state = viewModel.uiState.value as PreviewsUiState.Success
        assertEquals(2, state.previews.size)
        assertEquals("1", state.previews[0].id)
        assertEquals("2", state.previews[1].id)
        assertFalse(state.hasMorePreviews)
        assertFalse(viewModel.isLoadingMore.value)
    }

    @Test
    fun `refresh reloads previews from page 1`() = runTest(testDispatcher) {
        val projects = listOf(createProject(1, "tuist/tuist"))
        val initialPreviews = listOf(createPreview("1", "Preview 1"))
        val refreshedPreviews = listOf(createPreview("1", "Preview 1"), createPreview("3", "Preview 3"))

        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns projects
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 1) } returns
            PreviewsPage(initialPreviews, 1, false) andThen
            PreviewsPage(refreshedPreviews, 1, false)

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refresh()
        advanceUntilIdle()

        val state = viewModel.uiState.value as PreviewsUiState.Success
        assertEquals(refreshedPreviews, state.previews)
        assertFalse(viewModel.isRefreshing.value)
    }

    @Test
    fun `refresh sets Error state on failure`() = runTest(testDispatcher) {
        val projects = listOf(createProject(1, "tuist/tuist"))
        val previews = listOf(createPreview("1", "Preview 1"))

        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns projects
        coEvery { previewsRepository.listPreviews("tuist", "tuist", page = 1) } returns
            PreviewsPage(previews, 1, false) andThenThrows
            RuntimeException("Refresh failed")

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refresh()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is PreviewsUiState.Error)
        assertEquals("Refresh failed", (state as PreviewsUiState.Error).message)
        assertFalse(viewModel.isRefreshing.value)
    }

    @Test
    fun `signOut delegates to AuthRepository`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { previewsRepository.listProjects() } returns emptyList()
        every { authRepository.signOut() } returns Unit

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.signOut()

        verify(exactly = 1) { authRepository.signOut() }
    }

    private fun createProject(id: Int, fullName: String): Project {
        return Project(
            id = id,
            fullName = fullName,
            defaultBranch = "main",
            token = "",
            visibility = Project.Visibility.`public`,
            buildSystem = null,
            repositoryUrl = null,
        )
    }

    private fun createPreview(id: String, displayName: String): Preview {
        return Preview(
            id = id,
            url = "https://tuist.dev/preview/$id",
            iconUrl = "https://tuist.dev/icon/$id",
            deviceUrl = "https://tuist.dev/device/$id",
            qrCodeUrl = "https://tuist.dev/qr/$id",
            builds = emptyList(),
            supportedPlatforms = emptyList(),
            insertedAt = "2025-01-01T00:00:00Z",
            createdFromCi = false,
            displayName = displayName,
            gitBranch = "main",
            gitCommitSha = "abc1234567890",
        )
    }
}
