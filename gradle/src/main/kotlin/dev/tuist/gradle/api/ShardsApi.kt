package dev.tuist.gradle.api

import dev.tuist.gradle.api.model.CreateShardPlanParams1
import dev.tuist.gradle.api.model.Shard
import dev.tuist.gradle.api.model.ShardPlan
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
        @Body body: CreateShardPlanParams1
    ): Call<ShardPlan>

    @GET("api/projects/{account_handle}/{project_handle}/tests/shards/{plan_id}/{shard_index}")
    fun getShard(
        @Path("account_handle") accountHandle: String,
        @Path("project_handle") projectHandle: String,
        @Path("plan_id") planId: String,
        @Path("shard_index") shardIndex: Int
    ): Call<Shard>
}
