package dev.tuist.gradle

import com.google.gson.annotations.SerializedName
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.provider.Property
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.api.tasks.CacheableTask
import org.gradle.build.event.BuildEventsListenerRegistry
import org.gradle.caching.internal.operations.BuildCacheArchivePackBuildOperationType
import org.gradle.caching.internal.operations.BuildCacheLocalLoadBuildOperationType
import org.gradle.caching.internal.operations.BuildCacheRemoteLoadBuildOperationType
import org.gradle.api.internal.GradleInternal
import org.gradle.internal.operations.BuildOperationDescriptor
import org.gradle.internal.operations.BuildOperationListener
import org.gradle.internal.operations.BuildOperationListenerManager
import org.gradle.internal.operations.OperationFinishEvent
import org.gradle.internal.operations.OperationIdentifier
import org.gradle.internal.operations.OperationProgressEvent
import org.gradle.internal.operations.OperationStartEvent
import org.gradle.api.internal.tasks.execution.ExecuteTaskBuildOperationType
import org.gradle.tooling.events.FinishEvent
import org.gradle.tooling.events.OperationCompletionListener
import org.gradle.tooling.events.task.TaskFinishEvent
import org.gradle.tooling.events.task.TaskFailureResult
import org.gradle.tooling.events.task.TaskSkippedResult
import org.gradle.tooling.events.task.TaskSuccessResult
import com.google.gson.Gson
import org.gradle.api.logging.Logging
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject

// --- Data classes ---

enum class CacheHitType { LOCAL, REMOTE, MISS }

enum class TaskOutcome(val value: String) {
    @SerializedName("local_hit") LOCAL_HIT("local_hit"),
    @SerializedName("remote_hit") REMOTE_HIT("remote_hit"),
    @SerializedName("up_to_date") UP_TO_DATE("up_to_date"),
    @SerializedName("executed") EXECUTED("executed"),
    @SerializedName("failed") FAILED("failed"),
    @SerializedName("skipped") SKIPPED("skipped"),
    @SerializedName("no_source") NO_SOURCE("no_source");
}

data class TaskCacheMetadata(
    val cacheKey: String? = null,
    val artifactSize: Long? = null,
    val cacheHitType: CacheHitType = CacheHitType.MISS
)

data class TaskOutcomeData(
    val taskPath: String,
    val outcome: TaskOutcome,
    val cacheable: Boolean,
    val durationMs: Long,
    val cacheKey: String?,
    val cacheArtifactSize: Long?,
    val startedAt: String?
)

data class TaskReportEntry(
    @SerializedName("task_path") val taskPath: String,
    val outcome: TaskOutcome,
    val cacheable: Boolean,
    @SerializedName("duration_ms") val durationMs: Long,
    @SerializedName("cache_key") val cacheKey: String?,
    @SerializedName("cache_artifact_size") val cacheArtifactSize: Long?,
    @SerializedName("started_at") val startedAt: String?
)

data class BuildReportRequest(
    @SerializedName("duration_ms") val durationMs: Long,
    val status: String,
    @SerializedName("gradle_version") val gradleVersion: String?,
    @SerializedName("java_version") val javaVersion: String?,
    @SerializedName("is_ci") val isCi: Boolean,
    @SerializedName("git_branch") val gitBranch: String?,
    @SerializedName("git_commit_sha") val gitCommitSha: String?,
    @SerializedName("git_ref") val gitRef: String?,
    @SerializedName("root_project_name") val rootProjectName: String?,
    val tasks: List<TaskReportEntry>
)

data class BuildReportResponse(val id: String)

// --- Build Service ---

abstract class TuistBuildInsightsService :
    BuildService<TuistBuildInsightsService.Params>,
    OperationCompletionListener,
    BuildOperationListener,
    AutoCloseable {

    interface Params : BuildServiceParameters {
        val url: Property<String>
        val project: Property<String>
        val executablePath: Property<String>
        val gradleVersion: Property<String>
        val rootProjectName: Property<String>
    }

    private val logger = Logging.getLogger(TuistBuildInsightsService::class.java)

    internal var gitInfoProvider: GitInfoProvider = ProcessGitInfoProvider()
    internal var ciDetector: CIDetector = EnvironmentCIDetector()

    private val taskOutcomes = ConcurrentLinkedQueue<TaskOutcomeData>()
    private val cacheableTaskPaths = mutableSetOf<String>()
    private var buildStartTime: Long = System.currentTimeMillis()
    private var buildFailed = false

    private val operationParents = ConcurrentHashMap<OperationIdentifier, OperationIdentifier>()
    private val operationTaskPaths = ConcurrentHashMap<OperationIdentifier, String>()
    private val taskCacheMetadata = ConcurrentHashMap<String, TaskCacheMetadata>()

    fun setCacheableTasks(paths: Set<String>) {
        cacheableTaskPaths.addAll(paths)
    }

    override fun started(buildOperation: BuildOperationDescriptor, startEvent: OperationStartEvent) {
        val opId = buildOperation.id ?: return
        val parentId = buildOperation.parentId
        if (parentId != null) {
            operationParents[opId] = parentId
        }

        val details = buildOperation.details
        if (details is ExecuteTaskBuildOperationType.Details) {
            operationTaskPaths[opId] = details.taskPath
        }
    }

    override fun progress(operationIdentifier: OperationIdentifier, progressEvent: OperationProgressEvent) {
        // No-op
    }

    override fun finished(buildOperation: BuildOperationDescriptor, finishEvent: OperationFinishEvent) {
        val result = finishEvent.result
        val details = buildOperation.details
        val opId = buildOperation.id ?: return

        when (result) {
            is BuildCacheLocalLoadBuildOperationType.Result -> {
                if (result.isHit) {
                    val taskPath = findTaskPathForOperation(opId) ?: return
                    val cacheKey = (details as? BuildCacheLocalLoadBuildOperationType.Details)?.cacheKey
                    val existing = taskCacheMetadata[taskPath] ?: TaskCacheMetadata()
                    taskCacheMetadata[taskPath] = existing.copy(
                        cacheKey = cacheKey,
                        artifactSize = result.archiveSize,
                        cacheHitType = CacheHitType.LOCAL
                    )
                }
            }
            is BuildCacheRemoteLoadBuildOperationType.Result -> {
                if (result.isHit) {
                    val taskPath = findTaskPathForOperation(opId) ?: return
                    val cacheKey = (details as? BuildCacheRemoteLoadBuildOperationType.Details)?.cacheKey
                    val existing = taskCacheMetadata[taskPath] ?: TaskCacheMetadata()
                    taskCacheMetadata[taskPath] = existing.copy(
                        cacheKey = cacheKey,
                        artifactSize = result.archiveSize,
                        cacheHitType = CacheHitType.REMOTE
                    )
                }
            }
            is BuildCacheArchivePackBuildOperationType.Result -> {
                val taskPath = findTaskPathForOperation(opId) ?: return
                val cacheKey = (details as? BuildCacheArchivePackBuildOperationType.Details)?.cacheKey
                val existing = taskCacheMetadata[taskPath] ?: TaskCacheMetadata()
                taskCacheMetadata[taskPath] = existing.copy(
                    cacheKey = cacheKey,
                    artifactSize = result.archiveSize
                )
            }
        }

        // Clean up when task-level operations finish
        if (buildOperation.details is ExecuteTaskBuildOperationType.Details) {
            operationTaskPaths.remove(opId)
        }
        operationParents.remove(opId)
    }

    /**
     * Walks up the operation tree to find which Gradle task a nested build operation belongs to.
     *
     * Gradle's BuildOperationListener fires for operations at many levels — a cache load/store
     * operation is a child of the task execution operation, not the task itself. This method
     * follows [operationParents] (child → parent mappings recorded in [started]) upward until
     * it finds an operation that has an entry in [operationTaskPaths] (populated when an
     * ExecuteTaskBuildOperationType starts).
     *
     * For example, for a chain like `Task(:app:compileKotlin) → CacheLoad → …`, it walks from
     * the cache load op up to the task op and returns `:app:compileKotlin`.
     */
    private fun findTaskPathForOperation(opId: OperationIdentifier): String? {
        var currentId: OperationIdentifier? = opId
        while (currentId != null) {
            operationTaskPaths[currentId]?.let { return it }
            currentId = operationParents[currentId]
        }
        return null
    }

    override fun onFinish(event: FinishEvent) {
        if (event !is TaskFinishEvent) return
        val result = event.result
        val taskPath = event.descriptor.taskPath
        val durationMs = result.endTime - result.startTime
        val metadata = taskCacheMetadata[taskPath]

        val (outcome, cacheable) = when (result) {
            is TaskSuccessResult -> {
                when {
                    result.isFromCache -> {
                        val outcome = when (metadata?.cacheHitType) {
                            CacheHitType.REMOTE -> TaskOutcome.REMOTE_HIT
                            else -> TaskOutcome.LOCAL_HIT
                        }
                        outcome to true
                    }
                    result.isUpToDate -> TaskOutcome.UP_TO_DATE to cacheableTaskPaths.contains(taskPath)
                    else -> TaskOutcome.EXECUTED to cacheableTaskPaths.contains(taskPath)
                }
            }
            is TaskFailureResult -> {
                buildFailed = true
                TaskOutcome.FAILED to cacheableTaskPaths.contains(taskPath)
            }
            is TaskSkippedResult -> {
                val skipMessage = result.skipMessage ?: ""
                val outcome = if (skipMessage.contains("NO-SOURCE", ignoreCase = true)) TaskOutcome.NO_SOURCE else TaskOutcome.SKIPPED
                outcome to false
            }
            else -> TaskOutcome.EXECUTED to false
        }

        val startedAt = Instant.ofEpochMilli(result.startTime)
            .atOffset(ZoneOffset.UTC)
            .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

        taskOutcomes.add(
            TaskOutcomeData(
                taskPath = taskPath,
                outcome = outcome,
                cacheable = cacheable,
                durationMs = durationMs,
                cacheKey = metadata?.cacheKey,
                cacheArtifactSize = metadata?.artifactSize,
                startedAt = startedAt
            )
        )

        taskCacheMetadata.remove(taskPath)
    }

    override fun close() {
        try {
            sendReport()
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to send build insights: ${e.message}")
        }
    }

    private fun sendReport() {
        val projectValue = parameters.project.get()
        val parts = projectValue.split("/")
        if (parts.size != 2) {
            logger.warn("Tuist: Invalid project format for build insights: $projectValue")
            return
        }
        val (accountHandle, projectHandle) = parts

        val configProvider = TuistCommandConfigurationProvider(
            project = projectValue,
            command = listOf(parameters.executablePath.orNull ?: "tuist"),
            url = parameters.url.get()
        )

        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )

        val tasks = taskOutcomes.toList()
        val totalDurationMs = System.currentTimeMillis() - buildStartTime

        val status = when {
            buildFailed -> "failure"
            tasks.any { it.outcome == TaskOutcome.FAILED } -> "failure"
            else -> "success"
        }

        val report = BuildReportRequest(
            durationMs = totalDurationMs,
            status = status,
            gradleVersion = parameters.gradleVersion.orNull,
            javaVersion = System.getProperty("java.version"),
            isCi = ciDetector.isCi(),
            gitBranch = gitInfoProvider.branch(),
            gitCommitSha = gitInfoProvider.commitSha(),
            gitRef = gitInfoProvider.ref(),
            rootProjectName = parameters.rootProjectName.orNull,
            tasks = tasks.map { task ->
                TaskReportEntry(
                    taskPath = task.taskPath,
                    outcome = task.outcome,
                    cacheable = task.cacheable,
                    durationMs = task.durationMs,
                    cacheKey = task.cacheKey,
                    cacheArtifactSize = task.cacheArtifactSize,
                    startedAt = task.startedAt
                )
            }
        )

        val baseUrl = parameters.url.get().trimEnd('/')

        val response = httpClient.execute { config ->
            val url = URI("$baseUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")
            val connection = httpClient.openConnection(url, config)
            try {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")

                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    Gson().toJson(report, writer)
                }

                when (connection.responseCode) {
                    HttpURLConnection.HTTP_CREATED -> {
                        BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                            Gson().fromJson(reader, BuildReportResponse::class.java)
                        }
                    }
                    HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                    else -> null
                }
            } finally {
                connection.disconnect()
            }
        }

        if (response != null) {
            logger.lifecycle("Tuist: Build insights reported successfully (build ${response.id})")
        } else {
            logger.warn("Tuist: Failed to report build insights.")
        }
    }
}

// --- Project Plugin ---

internal abstract class TuistBuildInsightsPlugin @Inject constructor(
    private val eventsListenerRegistry: BuildEventsListenerRegistry
) : Plugin<Project> {
    private val logger = Logging.getLogger(TuistBuildInsightsPlugin::class.java)

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val url = project.findProperty("tuist.url") as? String ?: "https://tuist.dev"
        val tuistProject = project.findProperty("tuist.project") as? String ?: ""
        val executablePath = project.findProperty("tuist.executablePath") as? String ?: "tuist"
        val gradleVersion = project.gradle.gradleVersion

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistBuildInsights",
            TuistBuildInsightsService::class.java
        ) {
            parameters.url.set(url)
            parameters.project.set(tuistProject)
            parameters.executablePath.set(executablePath)
            parameters.gradleVersion.set(gradleVersion)
            parameters.rootProjectName.set(project.rootProject.name)
        }

        eventsListenerRegistry.onTaskCompletion(serviceProvider)

        project.gradle.taskGraph.whenReady {
            val cacheablePaths = allTasks
                .filter { task ->
                    task.javaClass.isAnnotationPresent(CacheableTask::class.java)
                }
                .map { it.path }
                .toSet()

            val service = serviceProvider.get()
            service.setCacheableTasks(cacheablePaths)

            try {
                val gradleInternal = project.gradle as GradleInternal
                val listenerManager = gradleInternal.services.get(BuildOperationListenerManager::class.java)
                listenerManager.addListener(service)
            } catch (e: Exception) {
                logger.warn("Tuist: Could not register build operation listener. Cache metadata may be incomplete.")
            }
        }
    }
}
