package dev.tuist.app.data.projects

import android.util.Log
import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.Project
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProjectsRepository @Inject constructor(
    private val projectsApi: ProjectsApi,
) {
    suspend fun listProjects(): Result<List<Project>> {
        return try {
            val response = projectsApi.listProjects()
            val body = response.body()
            if (!response.isSuccessful || body == null) {
                Log.e(TAG, "Failed to load projects: ${response.code()}")
                Result.failure(RuntimeException("Failed to load projects: ${response.code()}"))
            } else {
                Result.success(body.projects)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load projects", e)
            Result.failure(e)
        }
    }

    companion object {
        private const val TAG = "ProjectsRepository"
    }
}
