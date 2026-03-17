package dev.tuist.gradle.api

import dev.tuist.gradle.api.model.CreateShardPlanBody
import dev.tuist.gradle.api.model.ShardAssignmentResponse
import dev.tuist.gradle.api.model.ShardPlanResponse
import retrofit2.Call
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path

interface ShardsApi {
    @POST("api/projects/{account_handle}/{project_handle}/tests/shards")
    fun createShardPlan(
        @Path("account_handle") accountHandle: String,
        @Path("project_handle") projectHandle: String,
        @Body body: CreateShardPlanBody
    ): Call<ShardPlanResponse>

    @GET("api/projects/{account_handle}/{project_handle}/tests/shards/{session_id}/{shard_index}")
    fun getShardAssignment(
        @Path("account_handle") accountHandle: String,
        @Path("project_handle") projectHandle: String,
        @Path("session_id") sessionId: String,
        @Path("shard_index") shardIndex: Int
    ): Call<ShardAssignmentResponse>
}
