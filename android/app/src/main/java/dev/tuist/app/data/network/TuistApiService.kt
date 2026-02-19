package dev.tuist.app.data.network

import dev.tuist.app.data.model.ProjectsResponse
import retrofit2.http.GET

interface TuistApiService {
    @GET("api/projects")
    suspend fun listProjects(): ProjectsResponse
}
