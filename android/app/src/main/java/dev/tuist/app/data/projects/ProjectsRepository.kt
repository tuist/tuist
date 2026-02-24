package dev.tuist.app.data.projects

import dev.tuist.app.api.ProjectsApi
import dev.tuist.app.api.model.Project
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProjectsRepository @Inject constructor(
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
}
