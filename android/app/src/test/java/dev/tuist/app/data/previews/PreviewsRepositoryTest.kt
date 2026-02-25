package dev.tuist.app.data.previews

import com.squareup.moshi.Moshi
import dev.tuist.app.api.PreviewsApi
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.ListProjects200Response
import dev.tuist.app.api.model.PaginationMetadata
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.PreviewsIndex1
import dev.tuist.app.api.model.Project
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.Response

class PreviewsRepositoryTest {

    private lateinit var previewsApi: PreviewsApi
    private lateinit var projectsApi: ProjectsApi
    private lateinit var moshi: Moshi
    private lateinit var repository: PreviewsRepository

    @Before
    fun setUp() {
        previewsApi = mockk()
        projectsApi = mockk()
        moshi = Moshi.Builder().build()
        repository = PreviewsRepository(previewsApi, projectsApi, moshi)
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
        )
        coEvery { projectsApi.listProjects() } returns Response.success(ListProjects200Response(projects))

        val result = repository.listProjects()

        assertEquals(projects, result)
    }

    @Test
    fun `listProjects returns empty list when API returns no projects`() = runTest {
        coEvery { projectsApi.listProjects() } returns Response.success(ListProjects200Response(emptyList()))

        val result = repository.listProjects()

        assertTrue(result.isEmpty())
    }

    @Test(expected = RuntimeException::class)
    fun `listProjects propagates API exceptions`() = runTest {
        coEvery { projectsApi.listProjects() } throws RuntimeException("Network error")

        repository.listProjects()
    }

    @Test
    fun `listPreviews returns previews page from API`() = runTest {
        val previews = listOf(
            createPreview("1", "App Preview"),
        )
        val paginationMetadata = PaginationMetadata(
            hasNextPage = true,
            hasPreviousPage = false,
            pageSize = 10,
            totalCount = 15,
            currentPage = 1,
        )
        coEvery {
            previewsApi.listPreviews(
                accountHandle = "tuist",
                projectHandle = "tuist",
                page = 1,
                pageSize = 10,
            )
        } returns Response.success(PreviewsIndex1(paginationMetadata, previews))

        val result = repository.listPreviews("tuist", "tuist", page = 1, pageSize = 10)

        assertEquals(1, result.previews.size)
        assertEquals(1, result.currentPage)
        assertTrue(result.hasNextPage)
    }

    @Test
    fun `listPreviews returns no next page when at end`() = runTest {
        val paginationMetadata = PaginationMetadata(
            hasNextPage = false,
            hasPreviousPage = true,
            pageSize = 10,
            totalCount = 5,
            currentPage = 1,
        )
        coEvery {
            previewsApi.listPreviews(
                accountHandle = "tuist",
                projectHandle = "tuist",
                page = 1,
                pageSize = 10,
            )
        } returns Response.success(PreviewsIndex1(paginationMetadata, emptyList()))

        val result = repository.listPreviews("tuist", "tuist", page = 1, pageSize = 10)

        assertTrue(result.previews.isEmpty())
        assertFalse(result.hasNextPage)
    }

    @Test(expected = RuntimeException::class)
    fun `listPreviews propagates API exceptions`() = runTest {
        coEvery {
            previewsApi.listPreviews(
                accountHandle = "tuist",
                projectHandle = "tuist",
                page = 1,
                pageSize = 10,
            )
        } throws RuntimeException("Network error")

        repository.listPreviews("tuist", "tuist")
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
