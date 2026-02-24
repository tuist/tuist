package dev.tuist.app.ui.projects

import app.cash.turbine.test
import dev.tuist.app.api.model.Project
import dev.tuist.app.data.auth.AuthRepository
import dev.tuist.app.data.model.Account
import dev.tuist.app.data.model.AuthState
import dev.tuist.app.data.projects.ProjectsRepository
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
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ProjectsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var projectsRepository: ProjectsRepository
    private lateinit var authRepository: AuthRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        projectsRepository = mockk()
        authRepository = mockk()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(): ProjectsViewModel {
        return ProjectsViewModel(projectsRepository, authRepository)
    }

    @Test
    fun `loads projects after auth state becomes LoggedIn`() = runTest(testDispatcher) {
        val projects = listOf(
            Project(
                id = 1,
                fullName = "tuist/tuist",
                defaultBranch = "main",
                token = "",
                repositoryUrl = "https://github.com/tuist/tuist",
                visibility = Project.Visibility.`public`,
                buildSystem = Project.BuildSystem.xcode,
            ),
        )
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { projectsRepository.listProjects() } returns Result.success(projects)

        val viewModel = createViewModel()
        advanceUntilIdle()

        assertEquals(ProjectsUiState.Success(projects), viewModel.uiState.value)
    }

    @Test
    fun `sets Error state when loading fails`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { projectsRepository.listProjects() } returns Result.failure(RuntimeException("Network error"))

        val viewModel = createViewModel()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assert(state is ProjectsUiState.Error)
        assertEquals("Network error", (state as ProjectsUiState.Error).message)
    }

    @Test
    fun `refresh updates projects`() = runTest(testDispatcher) {
        val initialProjects = listOf(
            Project(id = 1, fullName = "tuist/tuist", defaultBranch = "main", token = "", visibility = Project.Visibility.`public`, buildSystem = null, repositoryUrl = null),
        )
        val refreshedProjects = listOf(
            Project(id = 1, fullName = "tuist/tuist", defaultBranch = "main", token = "", visibility = Project.Visibility.`public`, buildSystem = null, repositoryUrl = null),
            Project(id = 2, fullName = "tuist/cloud", defaultBranch = "main", token = "", visibility = Project.Visibility.`private`, buildSystem = null, repositoryUrl = null),
        )
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { projectsRepository.listProjects() } returns Result.success(initialProjects) andThen Result.success(refreshedProjects)

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refresh()
        advanceUntilIdle()

        assertEquals(ProjectsUiState.Success(refreshedProjects), viewModel.uiState.value)
        assertFalse(viewModel.isRefreshing.value)
    }

    @Test
    fun `signOut delegates to AuthRepository`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { projectsRepository.listProjects() } returns Result.success(emptyList())
        every { authRepository.signOut() } returns Unit

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.signOut()

        verify(exactly = 1) { authRepository.signOut() }
    }

    @Test
    fun `refresh sets Error state on failure`() = runTest(testDispatcher) {
        every { authRepository.authState } returns flowOf(
            AuthState.LoggedIn(Account(email = "test@test.com", handle = "test")),
        )
        coEvery { projectsRepository.listProjects() } returns Result.success(emptyList()) andThen Result.failure(RuntimeException("Refresh failed"))

        val viewModel = createViewModel()
        advanceUntilIdle()

        viewModel.refresh()
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assert(state is ProjectsUiState.Error)
        assertEquals("Refresh failed", (state as ProjectsUiState.Error).message)
        assertFalse(viewModel.isRefreshing.value)
    }
}
