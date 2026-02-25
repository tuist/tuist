package dev.tuist.app.data.previews

import com.squareup.moshi.Moshi
import dev.tuist.app.api.PreviewsApi
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.Preview
import dev.tuist.app.api.model.Project
import retrofit2.Response
import javax.inject.Inject
import javax.inject.Singleton

data class PreviewsPage(
    val previews: List<Preview>,
    val currentPage: Int?,
    val hasNextPage: Boolean,
)

sealed class ListProjectsError(message: String) : Exception(message) {
    class Unauthorized(message: String) : ListProjectsError(message)
    class Forbidden(message: String) : ListProjectsError(message)
    class Unknown(statusCode: Int) : ListProjectsError(
        "The projects could not be listed due to an unknown Tuist response of $statusCode.",
    )
}

sealed class ListPreviewsError(message: String) : Exception(message) {
    class Unauthorized(message: String) : ListPreviewsError(message)
    class Forbidden(message: String) : ListPreviewsError(message)
    class Unknown(statusCode: Int) : ListPreviewsError(
        "The previews could not be listed due to an unknown Tuist response of $statusCode.",
    )
}

sealed class GetPreviewError(message: String) : Exception(message) {
    class Unauthorized(message: String) : GetPreviewError(message)
    class Forbidden(message: String) : GetPreviewError(message)
    class NotFound(message: String) : GetPreviewError(message)
    class BadRequest(message: String) : GetPreviewError(message)
    class Unknown(statusCode: Int) : GetPreviewError(
        "The preview could not be loaded due to an unknown Tuist response of $statusCode.",
    )
}

sealed class DeletePreviewError(message: String) : Exception(message) {
    class Unauthorized(message: String) : DeletePreviewError(message)
    class Forbidden(message: String) : DeletePreviewError(message)
    class NotFound(message: String) : DeletePreviewError(message)
    class BadRequest(message: String) : DeletePreviewError(message)
    class Unknown(statusCode: Int) : DeletePreviewError(
        "The preview could not be deleted due to an unknown Tuist response of $statusCode.",
    )
}

@Singleton
class PreviewsRepository @Inject constructor(
    private val previewsApi: PreviewsApi,
    private val projectsApi: ProjectsApi,
    private val moshi: Moshi,
) {
    suspend fun listProjects(): List<Project> {
        val response = projectsApi.listProjects()
        val body = response.body()
        if (response.isSuccessful && body != null) {
            return body.projects
        }
        val message = response.serverErrorMessage()
        throw when (response.code()) {
            401 -> ListProjectsError.Unauthorized(message)
            403 -> ListProjectsError.Forbidden(message)
            else -> ListProjectsError.Unknown(response.code())
        }
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
        if (response.isSuccessful && body != null) {
            return body
        }
        val message = response.serverErrorMessage()
        throw when (response.code()) {
            400 -> GetPreviewError.BadRequest(message)
            401 -> GetPreviewError.Unauthorized(message)
            403 -> GetPreviewError.Forbidden(message)
            404 -> GetPreviewError.NotFound(message)
            else -> GetPreviewError.Unknown(response.code())
        }
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
        if (response.isSuccessful) return
        val message = response.serverErrorMessage()
        throw when (response.code()) {
            400 -> DeletePreviewError.BadRequest(message)
            401 -> DeletePreviewError.Unauthorized(message)
            403 -> DeletePreviewError.Forbidden(message)
            404 -> DeletePreviewError.NotFound(message)
            else -> DeletePreviewError.Unknown(response.code())
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
        if (response.isSuccessful && body != null) {
            return PreviewsPage(
                previews = body.previews,
                currentPage = body.paginationMetadata.currentPage,
                hasNextPage = body.paginationMetadata.hasNextPage,
            )
        }
        val message = response.serverErrorMessage()
        throw when (response.code()) {
            401 -> ListPreviewsError.Unauthorized(message)
            403 -> ListPreviewsError.Forbidden(message)
            else -> ListPreviewsError.Unknown(response.code())
        }
    }

    private fun <T> Response<T>.serverErrorMessage(): String {
        val errorJson = errorBody()?.string() ?: return ""
        return try {
            moshi.adapter(dev.tuist.app.api.model.Error::class.java)
                .fromJson(errorJson)?.message ?: ""
        } catch (_: Exception) {
            ""
        }
    }
}
