package dev.tuist.gradle.api.model

import com.google.gson.annotations.SerializedName

data class CreateShardPlanBody(
    @SerializedName("plan_id")
    val planId: String,
    @SerializedName("test_suites")
    val testSuites: List<String>?,
    @SerializedName("shard_min")
    val shardMin: Int?,
    @SerializedName("shard_max")
    val shardMax: Int?,
    @SerializedName("shard_max_duration")
    val shardMaxDuration: Int?,
    @SerializedName("granularity")
    val granularity: String = "suite"
)

data class ShardPlanResponse(
    @SerializedName("plan_id")
    val planId: String,
    @SerializedName("shard_count")
    val shardCount: Int,
    @SerializedName("shards")
    val shards: List<ShardAssignment>,
    @SerializedName("upload_id")
    val uploadId: String
)

data class ShardAssignment(
    @SerializedName("index")
    val index: Int,
    @SerializedName("test_targets")
    val testTargets: List<String>,
    @SerializedName("estimated_duration_ms")
    val estimatedDurationMs: Int
)

data class ShardAssignmentResponse(
    @SerializedName("test_targets")
    val testTargets: List<String>,
    @SerializedName("xctestrun_download_url")
    val xctestrunDownloadUrl: String?,
    @SerializedName("bundle_download_url")
    val bundleDownloadUrl: String?
)
