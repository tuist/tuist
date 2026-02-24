package dev.tuist.app.data.previews

import dev.tuist.app.api.PreviewsApi
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.Project
import javax.inject.Inject
import javax.inject.Singleton

data class PreviewsPage(
    val previews: List<Preview>,
    val currentPage: Int?,
    val hasNextPage: Boolean,
)

@Singleton
class PreviewsRepository @Inject constructor(
    private val previewsApi: PreviewsApi,
    private val projectsApi: ProjectsApi,
) {
    suspend fun listProjects(): List<Project> {
        val response = projectsApi.listProjects()
        val body = response.body()
        if (!response.isSuccessful || body == null) {
            throw RuntimeException("Failed to load projects: ${response.code()}")
        }
        return body.projects
    }

    suspend fun getPreview(
        accountHandle: String,
        projectHandle: String,
        previewId: String,
    ): Preview {
        val response = previewsApi.getPreview(
            accountHandle = accountHandle,
            projectHandle = projectHandle,
            previewId = previewId,
        )
        val body = response.body()
        if (!response.isSuccessful || body == null) {
            throw RuntimeException("Failed to load preview: ${response.code()}")
        }
        return body
    }

    suspend fun deletePreview(
        accountHandle: String,
        projectHandle: String,
        previewId: String,
    ) {
        val response = previewsApi.deletePreview(
            accountHandle = accountHandle,
            projectHandle = projectHandle,
            previewId = previewId,
        )
        if (!response.isSuccessful) {
            throw RuntimeException("Failed to delete preview: ${response.code()}")
        }
    }

    suspend fun listPreviews(
        accountHandle: String,
        projectHandle: String,
        page: Int = 1,
        pageSize: Int = 10,
    ): PreviewsPage {
        val response = previewsApi.listPreviews(
            accountHandle = accountHandle,
            projectHandle = projectHandle,
            page = page,
            pageSize = pageSize,
        )
        val body = response.body()
        if (!response.isSuccessful || body == null) {
            throw RuntimeException("Failed to load previews: ${response.code()}")
        }
        return PreviewsPage(
            previews = body.previews,
            currentPage = body.paginationMetadata.currentPage,
            hasNextPage = body.paginationMetadata.hasNextPage,
        )
    }
}
