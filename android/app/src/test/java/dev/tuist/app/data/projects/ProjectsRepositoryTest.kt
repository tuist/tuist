package dev.tuist.app.data.projects

import dev.tuist.app.data.model.ProjectsResponse
import dev.tuist.app.data.model.ServerProject
import dev.tuist.app.data.network.TuistApiService
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ProjectsRepositoryTest {

    private lateinit var apiService: TuistApiService
    private lateinit var repository: ProjectsRepository

    @Before
    fun setUp() {
        apiService = mockk()
        repository = ProjectsRepository(apiService)
    }

    @Test
    fun `listProjects returns projects from API`() = runTest {
        val projects = listOf(
            ServerProject(
                id = 1,
                fullName = "tuist/tuist",
                defaultBranch = "main",
                repositoryUrl = "https://github.com/tuist/tuist",
                visibility = "public",
                buildSystem = "xcode",
            ),
            ServerProject(
                id = 2,
                fullName = "tuist/cloud",
                defaultBranch = "main",
                repositoryUrl = null,
                visibility = "private",
                buildSystem = null,
            ),
        )
        coEvery { apiService.listProjects() } returns ProjectsResponse(projects)

        val result = repository.listProjects()

        assertEquals(projects, result)
    }

    @Test
    fun `listProjects returns empty list when API returns no projects`() = runTest {
        coEvery { apiService.listProjects() } returns ProjectsResponse(emptyList())

        val result = repository.listProjects()

        assertTrue(result.isEmpty())
    }

    @Test(expected = RuntimeException::class)
    fun `listProjects propagates API exceptions`() = runTest {
        coEvery { apiService.listProjects() } throws RuntimeException("Network error")

        repository.listProjects()
    }
}
