package dev.tuist.gradle

import com.google.gson.annotations.SerializedName
import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.api.tasks.CacheableTask
import org.gradle.caching.internal.operations.BuildCacheArchivePackBuildOperationType
import org.gradle.caching.internal.operations.BuildCacheLocalLoadBuildOperationType
import org.gradle.caching.internal.operations.BuildCacheRemoteLoadBuildOperationType
import org.gradle.caching.internal.operations.BuildCacheRemoteStoreBuildOperationType
import org.gradle.internal.operations.BuildOperationDescriptor
import org.gradle.internal.operations.OperationFinishEvent
import org.gradle.internal.taskgraph.CalculateTaskGraphBuildOperationType
import java.time.Instant

data class TaskExecutionTelemetry(
    @SerializedName("build_path") val buildPath: String,
    @SerializedName("task_type") val taskType: String,
    val cacheability: String,
    val incremental: Boolean,
    @SerializedName("remote_cache_lookup_outcome") val remoteCacheLookupOutcome: String,
    @SerializedName("remote_cache_download_duration_ms") val remoteCacheDownloadDurationMs: Long?,
    @SerializedName("remote_cache_upload_duration_ms") val remoteCacheUploadDurationMs: Long?
)

/**
 * Receives ordered completion events through Gradle's configuration-cache-aware
 * listener registry. Nested cache operations finish before their owning task:
 * carry their metadata up the operation tree without retaining every operation.
 */
internal class BuildExecutionTelemetry {
    private data class CacheWork(
        val key: String? = null,
        val size: Long? = null,
        val hit: CacheHitType? = null,
        val lookup: String = "not_requested",
        val downloadMs: Long? = null,
        val uploadMs: Long? = null,
        val stored: Boolean? = null
    ) {
        fun merge(other: CacheWork) = CacheWork(
            other.key ?: key, other.size ?: size, other.hit ?: hit,
            if (other.lookup != "not_requested") other.lookup else lookup,
            sum(downloadMs, other.downloadMs),
            sum(uploadMs, other.uploadMs), other.stored ?: stored
        )

        private fun sum(a: Long?, b: Long?): Long? = if (a == null && b == null) null else (a ?: 0) + (b ?: 0)
    }

    private val pending = mutableMapOf<Long, CacheWork>()
    val tasks = mutableListOf<TaskOutcomeData>()
    val requestedTasks = linkedSetOf<String>()
    var firstEventAt: Long? = null
        private set
    var lastTaskAt: Long? = null
        private set

    fun finished(operation: BuildOperationDescriptor, event: OperationFinishEvent) {
        firstEventAt = minOf(firstEventAt ?: event.startTime, event.startTime)
        val duration = (event.endTime - event.startTime).coerceAtLeast(0)
        val details = operation.details
        val result = event.result
        val operationId = operation.id?.id ?: return
        var work = pending.remove(operationId) ?: CacheWork()
        work = work.merge(when (details) {
            is BuildCacheLocalLoadBuildOperationType.Details -> {
                val load = result as? BuildCacheLocalLoadBuildOperationType.Result
                CacheWork(key = details.cacheKey, size = load?.takeIf { it.isHit }?.archiveSize,
                    hit = if (load?.isHit == true) CacheHitType.LOCAL else null)
            }
            is BuildCacheRemoteLoadBuildOperationType.Details -> {
                val load = result as? BuildCacheRemoteLoadBuildOperationType.Result
                val outcome = when {
                    event.failure != null || load == null -> "error"
                    load.isHit -> "hit"
                    else -> "miss"
                }
                CacheWork(key = details.cacheKey, size = load?.takeIf { it.isHit }?.archiveSize,
                    hit = if (outcome == "hit") CacheHitType.REMOTE else null,
                    lookup = outcome, downloadMs = if (outcome == "hit") duration else null)
            }
            is BuildCacheRemoteStoreBuildOperationType.Details -> CacheWork(
                key = details.cacheKey, uploadMs = duration,
                stored = (result as? BuildCacheRemoteStoreBuildOperationType.Result)?.isStored ?: false)
            is BuildCacheArchivePackBuildOperationType.Details -> CacheWork(
                key = details.cacheKey, size = (result as? BuildCacheArchivePackBuildOperationType.Result)?.archiveSize)
            else -> CacheWork()
        })

        if (details is ExecuteTaskBuildOperationType.Details && result is ExecuteTaskBuildOperationType.Result) {
            val outcome = when {
                event.failure != null -> TaskOutcome.FAILED
                work.hit == CacheHitType.REMOTE -> TaskOutcome.REMOTE_HIT
                work.hit == CacheHitType.LOCAL -> TaskOutcome.LOCAL_HIT
                result.skipMessage == "FROM-CACHE" -> TaskOutcome.CACHE_HIT
                result.skipMessage == "NO-SOURCE" -> TaskOutcome.NO_SOURCE
                result.skipMessage == "UP-TO-DATE" -> TaskOutcome.UP_TO_DATE
                result.skipMessage != null -> TaskOutcome.SKIPPED
                else -> TaskOutcome.EXECUTED
            }
            val cacheability = when {
                work.hit != null || work.key != null -> "cacheable"
                result.cachingDisabledReasonCategory !in listOf(null, "UNKNOWN", "BUILD_CACHE_DISABLED") -> "disabled"
                details.taskClass.isAnnotationPresent(CacheableTask::class.java) -> "cacheable"
                else -> "unknown"
            }
            val startedAt = Instant.ofEpochMilli(event.startTime).toString()
            tasks.add(TaskOutcomeData(
                taskPath = details.taskPath, outcome = outcome, cacheable = cacheability == "cacheable",
                durationMs = duration, cacheKey = work.key, cacheArtifactSize = work.size,
                startedAt = startedAt, remoteCacheMiss = work.lookup == "miss", remoteCacheStored = work.stored,
                execution = TaskExecutionTelemetry(details.buildPath,
                    details.taskClass.name.removeSuffix("_Decorated"), cacheability,
                    result.isIncremental, work.lookup, work.downloadMs, work.uploadMs)
            ))
            lastTaskAt = maxOf(lastTaskAt ?: event.endTime, event.endTime)
        } else if (work != CacheWork()) {
            operation.parentId?.id?.let { parent -> pending[parent] = (pending[parent] ?: CacheWork()).merge(work) }
        }

        if (result is CalculateTaskGraphBuildOperationType.Result) {
            requestedTasks.addAll(result.requestedTaskPaths)
        }
    }
}
