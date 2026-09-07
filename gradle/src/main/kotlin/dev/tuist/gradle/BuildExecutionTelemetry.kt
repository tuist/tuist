package dev.tuist.gradle

import com.google.gson.GsonBuilder
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
import org.gradle.internal.taskgraph.NodeIdentity
import org.gradle.operations.dependencies.transforms.ExecutePlannedTransformStepBuildOperationType
import org.gradle.operations.dependencies.transforms.PlannedTransformStepIdentity
import java.time.Instant

data class TaskExecutionTelemetry(
    @SerializedName("build_path") val buildPath: String,
    @SerializedName("project_path") val projectPath: String,
    @SerializedName("task_type") val taskType: String,
    val cacheability: String,
    @SerializedName("caching_disabled_reason") val cachingDisabledReason: String?,
    @SerializedName("execution_reasons") val executionReasons: List<String>,
    val incremental: Boolean,
    @SerializedName("remote_cache_lookup_outcome") val remoteCacheLookupOutcome: String,
    @SerializedName("remote_cache_lookup_duration_ms") val remoteCacheLookupDurationMs: Long?,
    @SerializedName("remote_cache_download_duration_ms") val remoteCacheDownloadDurationMs: Long?,
    @SerializedName("remote_cache_upload_duration_ms") val remoteCacheUploadDurationMs: Long?
)

data class ExecutionNode(
    val id: String,
    val kind: String,
    @SerializedName("build_path") val buildPath: String,
    @SerializedName("project_path") val projectPath: String,
    val label: String,
    val dependencies: List<String>,
    @SerializedName("must_run_after") val mustRunAfter: List<String> = emptyList(),
    @SerializedName("should_run_after") val shouldRunAfter: List<String> = emptyList(),
    @SerializedName("finalized_by") val finalizedBy: List<String> = emptyList(),
    @SerializedName("duration_ms") val durationMs: Long? = null,
    @SerializedName("started_at") val startedAt: String? = null
)

data class ExecutionGraph(val status: String, val nodes: List<ExecutionNode>)

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
        val lookupMs: Long? = null,
        val downloadMs: Long? = null,
        val uploadMs: Long? = null,
        val stored: Boolean? = null
    ) {
        fun merge(other: CacheWork) = CacheWork(
            other.key ?: key, other.size ?: size, other.hit ?: hit,
            if (other.lookup != "not_requested") other.lookup else lookup,
            sum(lookupMs, other.lookupMs), sum(downloadMs, other.downloadMs),
            sum(uploadMs, other.uploadMs), other.stored ?: stored
        )

        private fun sum(a: Long?, b: Long?): Long? = if (a == null && b == null) null else (a ?: 0) + (b ?: 0)
    }

    private val pending = mutableMapOf<Long, CacheWork>()
    private val nodes = linkedMapOf<String, ExecutionNode>()
    private var edgeCount = 0
    private val timings = mutableMapOf<String, Pair<Long, String>>()
    val tasks = mutableListOf<TaskOutcomeData>()
    var graphCaptured = false
        private set
    var incomplete = false
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
                    lookup = outcome, lookupMs = duration, downloadMs = if (outcome == "hit") duration else null)
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
                execution = TaskExecutionTelemetry(details.buildPath, projectPath(details.taskPath),
                    details.taskClass.name.removeSuffix("_Decorated"), cacheability,
                    result.cachingDisabledReasonMessage, result.upToDateMessages.orEmpty().take(100),
                    result.isIncremental, work.lookup, work.lookupMs, work.downloadMs, work.uploadMs)
            ))
            timings[taskId(details.buildPath, details.taskPath)] = duration to startedAt
            lastTaskAt = maxOf(lastTaskAt ?: event.endTime, event.endTime)
        } else if (work != CacheWork()) {
            operation.parentId?.id?.let { parent -> pending[parent] = (pending[parent] ?: CacheWork()).merge(work) }
        }

        if (result is CalculateTaskGraphBuildOperationType.Result) {
            requestedTasks.addAll(result.requestedTaskPaths)
            val plan = result.getExecutionPlan(NodeIdentity.NodeType.values().toSet())
            if (plan.size > MAX_NODES) {
                incomplete = true
            } else {
                plan.forEach { node ->
                    val identity = node.nodeIdentity
                    val task = node as? CalculateTaskGraphBuildOperationType.PlannedTask
                    val transform = identity as? PlannedTransformStepIdentity
                    val taskIdentity = identity as? CalculateTaskGraphBuildOperationType.TaskIdentity
                    val buildPath = taskIdentity?.buildPath ?: transform?.consumerBuildPath ?: ":"
                    val label = taskIdentity?.taskPath ?: transform?.artifactName ?: identity.toString()
                    val captured = ExecutionNode(
                        id = nodeId(identity), kind = if (taskIdentity != null) "task" else "transform",
                        buildPath = buildPath, projectPath = taskIdentity?.let { projectPath(it.taskPath) }
                            ?: transform?.consumerProjectPath.orEmpty(), label = label,
                        dependencies = node.nodeDependencies.map(::nodeId).distinct(),
                        mustRunAfter = task?.mustRunAfter.orEmpty().map(::nodeId),
                        shouldRunAfter = task?.shouldRunAfter.orEmpty().map(::nodeId),
                        finalizedBy = task?.finalizedBy.orEmpty().map(::nodeId)
                    )
                    val previous = nodes[captured.id]
                    val delta = edgeCount(captured) - (previous?.let(::edgeCount) ?: 0)
                    if ((previous != null || nodes.size < MAX_NODES) && edgeCount + delta <= MAX_EDGES) {
                        nodes[captured.id] = captured
                        edgeCount += delta
                    } else {
                        incomplete = true
                    }
                }
                graphCaptured = true
            }
        }
        if (details is ExecutePlannedTransformStepBuildOperationType.Details) {
            timings[nodeId(details.plannedTransformStepIdentity)] = duration to Instant.ofEpochMilli(event.startTime).toString()
        }
    }

    fun graph(): ExecutionGraph {
        val captured = nodes.values.map { node ->
            val timing = timings[node.id]
            node.copy(durationMs = timing?.first, startedAt = timing?.second)
        }
        val missing = captured.any { node -> node.dependencies.any { it !in nodes } }
        return ExecutionGraph(when {
            incomplete || missing -> "partial"
            graphCaptured -> "complete"
            else -> "unavailable"
        }, captured)
    }

    private fun edgeCount(node: ExecutionNode) = node.dependencies.size + node.mustRunAfter.size +
        node.shouldRunAfter.size + node.finalizedBy.size

    private fun nodeId(identity: NodeIdentity): String = when (identity) {
        is CalculateTaskGraphBuildOperationType.TaskIdentity -> taskId(identity.buildPath, identity.taskPath)
        is PlannedTransformStepIdentity -> "transform:${identity.transformStepNodeId}"
        else -> { incomplete = true; "unknown:${identity}" }
    }

    companion object {
        const val MAX_NODES = 20_000
        const val MAX_EDGES = 100_000
        private val identityJson = GsonBuilder().disableHtmlEscaping().create()
        fun taskId(buildPath: String, taskPath: String): String = identityJson.toJson(listOf(buildPath, taskPath))
        fun projectPath(taskPath: String): String = taskPath.substringBeforeLast(':').ifEmpty { ":" }
    }
}
