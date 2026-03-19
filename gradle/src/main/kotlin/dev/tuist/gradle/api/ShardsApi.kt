package dev.tuist.gradle.api

import retrofit2.http.*
import retrofit2.Call
import okhttp3.RequestBody
import com.google.gson.annotations.SerializedName

import dev.tuist.gradle.api.model.CompleteShardUpload200Response
import dev.tuist.gradle.api.model.CompleteShardUploadParams1
import dev.tuist.gradle.api.model.CreateShardPlanParams1
import dev.tuist.gradle.api.model.Error
import dev.tuist.gradle.api.model.GenerateShardUploadURL200Response
import dev.tuist.gradle.api.model.GenerateShardUploadURLParams1
import dev.tuist.gradle.api.model.Shard
import dev.tuist.gradle.api.model.ShardPlan
import dev.tuist.gradle.api.model.StartShardUpload200Response
import dev.tuist.gradle.api.model.StartShardUploadParams1

interface ShardsApi {
    /**
     * POST api/projects/{account_handle}/{project_handle}/tests/shards/upload/complete
     * Complete the multipart upload and trigger per-shard xctestrun creation.
     * 
     * Responses:
     *  - 200: Upload completed
     *  - 401: You need to be authenticated
     *  - 403: The authenticated subject is not authorized
     *
     * @param accountHandle The handle of the project&#39;s account.
     * @param projectHandle The handle of the project.
     * @param completeShardUploadParams1 Complete upload params (optional)
     * @return [Call]<[CompleteShardUpload200Response]>
     */
    @POST("api/projects/{account_handle}/{project_handle}/tests/shards/upload/complete")
    fun completeShardUpload(@Path("account_handle") accountHandle: kotlin.String, @Path("project_handle") projectHandle: kotlin.String, @Body completeShardUploadParams1: CompleteShardUploadParams1? = null): Call<CompleteShardUpload200Response>

    /**
     * POST api/projects/{account_handle}/{project_handle}/tests/shards
     * Create a shard plan.
     * Creates a new test sharding session that distributes test targets across multiple CI runners.
     * Responses:
     *  - 200: The shard plan
     *  - 400: Invalid parameters
     *  - 401: You need to be authenticated
     *  - 403: The authenticated subject is not authorized
     *  - 404: The project doesn't exist
     *
     * @param accountHandle The handle of the project&#39;s account.
     * @param projectHandle The handle of the project.
     * @param createShardPlanParams1 Shard plan params (optional)
     * @return [Call]<[ShardPlan]>
     */
    @POST("api/projects/{account_handle}/{project_handle}/tests/shards")
    fun createShardPlan(@Path("account_handle") accountHandle: kotlin.String, @Path("project_handle") projectHandle: kotlin.String, @Body createShardPlanParams1: CreateShardPlanParams1? = null): Call<ShardPlan>

    /**
     * POST api/projects/{account_handle}/{project_handle}/tests/shards/upload/generate-url
     * Generate a signed URL for uploading a part of the test bundle.
     * 
     * Responses:
     *  - 200: The signed URL
     *  - 401: You need to be authenticated
     *  - 403: The authenticated subject is not authorized
     *
     * @param accountHandle The handle of the project&#39;s account.
     * @param projectHandle The handle of the project.
     * @param generateShardUploadURLParams1 Upload URL params (optional)
     * @return [Call]<[GenerateShardUploadURL200Response]>
     */
    @POST("api/projects/{account_handle}/{project_handle}/tests/shards/upload/generate-url")
    fun generateShardUploadURL(@Path("account_handle") accountHandle: kotlin.String, @Path("project_handle") projectHandle: kotlin.String, @Body generateShardUploadURLParams1: GenerateShardUploadURLParams1? = null): Call<GenerateShardUploadURL200Response>

    /**
     * GET api/projects/{account_handle}/{project_handle}/tests/shards/{reference}/{shard_index}
     * Get a shard.
     * Returns the test targets and download URLs for a specific shard.
     * Responses:
     *  - 200: The shard
     *  - 401: You need to be authenticated
     *  - 403: The authenticated subject is not authorized
     *  - 404: The session or shard was not found
     *
     * @param accountHandle The handle of the project&#39;s account.
     * @param projectHandle The handle of the project.
     * @param reference The shard plan reference.
     * @param shardIndex The zero-based shard index.
     * @return [Call]<[Shard]>
     */
    @GET("api/projects/{account_handle}/{project_handle}/tests/shards/{reference}/{shard_index}")
    fun getShard(@Path("account_handle") accountHandle: kotlin.String, @Path("project_handle") projectHandle: kotlin.String, @Path("reference") reference: kotlin.String, @Path("shard_index") shardIndex: kotlin.Int): Call<Shard>

    /**
     * POST api/projects/{account_handle}/{project_handle}/tests/shards/upload/start
     * Start a multipart upload for the test products bundle.
     * 
     * Responses:
     *  - 200: The upload ID
     *  - 401: You need to be authenticated
     *  - 403: The authenticated subject is not authorized
     *
     * @param accountHandle The handle of the project&#39;s account.
     * @param projectHandle The handle of the project.
     * @param startShardUploadParams1 Start upload params (optional)
     * @return [Call]<[StartShardUpload200Response]>
     */
    @POST("api/projects/{account_handle}/{project_handle}/tests/shards/upload/start")
    fun startShardUpload(@Path("account_handle") accountHandle: kotlin.String, @Path("project_handle") projectHandle: kotlin.String, @Body startShardUploadParams1: StartShardUploadParams1? = null): Call<StartShardUpload200Response>

}
