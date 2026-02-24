package dev.tuist.app.data.projects

import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.ListProjects200Response
import dev.tuist.app.api.model.Project
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.Response

class ProjectsRepositoryTest {

    private lateinit var projectsApi: ProjectsApi
    private lateinit var repository: ProjectsRepository

    @Before
    fun setUp() {
        projectsApi = mockk()
        repository = ProjectsRepository(projectsApi)
    }

    @Test
    fun `listProjects returns projects from API`() = runTest {
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
            Project(
                id = 2,
                fullName = "tuist/cloud",
                defaultBranch = "main",
                token = "",
                repositoryUrl = null,
                visibility = Project.Visibility.`private`,
                buildSystem = null,
            ),
        )
        coEvery { projectsApi.listProjects() } returns Response.success(ListProjects200Response(projects))

        val result = repository.listProjects()

        assertEquals(projects, result.getOrThrow())
    }

    @Test
    fun `listProjects returns empty list when API returns no projects`() = runTest {
        coEvery { projectsApi.listProjects() } returns Response.success(ListProjects200Response(emptyList()))

        val result = repository.listProjects()

        assertTrue(result.getOrThrow().isEmpty())
    }

    @Test
    fun `listProjects returns failure when API throws`() = runTest {
        coEvery { projectsApi.listProjects() } throws RuntimeException("Network error")

        val result = repository.listProjects()

        assertTrue(result.isFailure)
        assertEquals("Network error", result.exceptionOrNull()?.message)
    }
}
