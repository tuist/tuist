package dev.tuist.app.data.projects

import dev.tuist.app.data.model.ServerProject
import dev.tuist.app.data.network.TuistApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProjectsRepository @Inject constructor(
    private val apiService: TuistApiService,
) {
    suspend fun listProjects(): List<ServerProject> =
        apiService.listProjects().projects
}
