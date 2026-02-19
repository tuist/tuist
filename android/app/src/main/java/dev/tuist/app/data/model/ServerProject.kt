package dev.tuist.app.data.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class ServerProject(
    val id: Int,
    @Json(name = "full_name") val fullName: String,
    @Json(name = "default_branch") val defaultBranch: String,
    @Json(name = "repository_url") val repositoryUrl: String?,
    val visibility: String,
    @Json(name = "build_system") val buildSystem: String?,
)

@JsonClass(generateAdapter = true)
data class ProjectsResponse(
    val projects: List<ServerProject>,
)
