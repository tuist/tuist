package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.Plugin
import org.gradle.api.model.ObjectFactory
import org.gradle.api.Project
import org.gradle.internal.build.event.BuildEventListenerRegistryInternal
import org.gradle.api.logging.Logging
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.MapProperty
import org.gradle.api.provider.Property
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.build.event.BuildEventsListenerRegistry
import org.gradle.configuration.project.ConfigureProjectBuildOperationType
import org.gradle.initialization.ConfigureBuildBuildOperationType
import org.gradle.initialization.EvaluateSettingsBuildOperationType
import org.gradle.internal.configurationcache.ConfigurationCacheLoadBuildOperationType
import org.gradle.internal.operations.BuildOperationDescriptor
import org.gradle.internal.operations.BuildOperationListener
import org.gradle.internal.operations.OperationFinishEvent
import org.gradle.internal.operations.OperationIdentifier
import org.gradle.internal.operations.OperationProgressEvent
import org.gradle.internal.operations.OperationStartEvent
import org.gradle.operations.configuration.ConfigurationCacheCheckFingerprintBuildOperationType
import org.gradle.operations.dependencies.transforms.ExecutePlannedTransformStepBuildOperationType
import org.gradle.internal.cc.impl.InputTrackingState
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject

// --- Data classes ---

enum class CacheHitType { LOCAL, REMOTE }

enum class TaskOutcome(val value: String) {
    @SerializedName("cache_hit") CACHE_HIT("cache_hit"),
    @SerializedName("local_hit") LOCAL_HIT("local_hit"),
    @SerializedName("remote_hit") REMOTE_HIT("remote_hit"),
    @SerializedName("up_to_date") UP_TO_DATE("up_to_date"),
    @SerializedName("executed") EXECUTED("executed"),
    @SerializedName("failed") FAILED("failed"),
    @SerializedName("skipped") SKIPPED("skipped"),
    @SerializedName("no_source") NO_SOURCE("no_source");
}

data class TaskOutcomeData(
    val taskPath: String,
    val outcome: TaskOutcome,
    val cacheable: Boolean,
    val durationMs: Long,
    val cacheKey: String?,
    val cacheArtifactSize: Long?,
    val startedAt: String?,
    val remoteCacheMiss: Boolean = false,
    val remoteCacheStored: Boolean? = null,
    val execution: TaskExecutionTelemetry? = null
)

data class TaskReportEntry(
    @SerializedName("task_path") val taskPath: String,
    val outcome: TaskOutcome,
    val cacheable: Boolean,
    @SerializedName("duration_ms") val durationMs: Long,
    @SerializedName("cache_key") val cacheKey: String?,
    @SerializedName("cache_artifact_size") val cacheArtifactSize: Long?,
    @SerializedName("started_at") val startedAt: String?,
    @SerializedName("remote_cache_miss") val remoteCacheMiss: Boolean = false,
    @SerializedName("remote_cache_stored") val remoteCacheStored: Boolean? = null,
    val execution: TaskExecutionTelemetry? = null
)

data class ConfigurationCacheReport(
    val status: String,
    @SerializedName("entry_size") val entrySize: Long? = null,
    @SerializedName("load_duration_ms") val loadDurationMs: Long? = null,
    @SerializedName("invalidation_reasons") val invalidationReasons: List<String> = emptyList()
)

data class ConfigurationOperationReportEntry(
    val phase: String,
    @SerializedName("build_path") val buildPath: String,
    @SerializedName("project_path") val projectPath: String? = null,
    @SerializedName("duration_ms") val durationMs: Long,
    @SerializedName("started_at") val startedAt: String
)

data class ArtifactTransformReportEntry(
    @SerializedName("transformer_name") val transformerName: String,
    @SerializedName("transform_action_class") val transformActionClass: String,
    @SerializedName("subject_name") val subjectName: String,
    @SerializedName("artifact_name") val artifactName: String,
    @SerializedName("consumer_project_path") val consumerProjectPath: String,
    @SerializedName("duration_ms") val durationMs: Long,
    @SerializedName("started_at") val startedAt: String
)

data class BuildReportRequest(
    val id: String,
    @SerializedName("duration_ms") val durationMs: Long,
    val status: String,
    @SerializedName("gradle_version") val gradleVersion: String?,
    @SerializedName("java_version") val javaVersion: String?,
    @SerializedName("is_ci") val isCi: Boolean,
    @SerializedName("git_branch") val gitBranch: String?,
    @SerializedName("git_commit_sha") val gitCommitSha: String?,
    @SerializedName("git_ref") val gitRef: String?,
    @SerializedName("git_remote_url_origin") val gitRemoteUrlOrigin: String?,
    @SerializedName("root_project_name") val rootProjectName: String?,
    @SerializedName("requested_tasks") val requestedTasks: List<String>,
    val tasks: List<TaskReportEntry>,
    @SerializedName("machine_metrics") val machineMetrics: List<MachineMetricSample>? = null,
    @SerializedName("custom_metadata") val customMetadata: BuildCustomMetadata = BuildCustomMetadata(),
    @SerializedName("configuration_cache") val configurationCache: ConfigurationCacheReport? = null,
    @SerializedName("configuration_operations") val configurationOperations: List<ConfigurationOperationReportEntry> = emptyList(),
    @SerializedName("artifact_transforms") val artifactTransforms: List<ArtifactTransformReportEntry> = emptyList(),
)

data class BuildReportResponse(val id: String)

// --- Build Service ---

abstract class TuistBuildInsightsService :
    BuildService<TuistBuildInsightsService.Params>,
    BuildOperationListener,
    AutoCloseable {

    interface Params : BuildServiceParameters {
        val url: Property<String>
        val project: Property<String>
        val useEnvironmentProxy: Property<Boolean>
        val gradleVersion: Property<String>
        val rootProjectName: Property<String>
        val projectDir: DirectoryProperty
        val customTags: ListProperty<String>
        val customValues: MapProperty<String, String>
        val gitBranch: Property<String>
        val gitCommitSha: Property<String>
        val gitRef: Property<String>
        val gitRemoteUrlOrigin: Property<String>
        val requestedTasks: ListProperty<String>
        val backgroundUpload: Property<Boolean>
    }

    private val logger = Logging.getLogger(TuistBuildInsightsService::class.java)

    @get:Inject
    abstract val objects: ObjectFactory

    private val machineMetricsCollector = MachineMetricsCollector(
        inputTrackingState = objects.newInstance(MetricsInputTracking::class.java).state
    ).also { it.start() }

    internal var gitInfoProvider: GitInfoProvider? = null
    internal var ciDetector: CIDetector = EnvironmentCIDetector()
    internal var uploadInBackground: Boolean? = null

    val buildId: String = UUID.randomUUID().toString()

    private val executionTelemetry = BuildExecutionTelemetry()
    private val configurationOperations = ConcurrentLinkedQueue<ConfigurationOperationReportEntry>()
    private val artifactTransforms = ConcurrentLinkedQueue<ArtifactTransformReportEntry>()
    private val buildStartTime = System.currentTimeMillis()
    private val configurationCacheInvalidationReasons = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var configurationCacheStatus: String? = null
    @Volatile private var configurationCacheEntrySize: Long? = null
    @Volatile private var configurationCacheLoadDurationMs: Long? = null

    override fun started(buildOperation: BuildOperationDescriptor, startEvent: OperationStartEvent) = Unit

    override fun progress(operationIdentifier: OperationIdentifier, progressEvent: OperationProgressEvent) = Unit

    override fun finished(buildOperation: BuildOperationDescriptor, finishEvent: OperationFinishEvent) {
        try {
            executionTelemetry.finished(buildOperation, finishEvent)
            recordConfigurationOperation(buildOperation.details, finishEvent)
            recordConfigurationCacheMetadata(finishEvent.result, finishEvent)
            recordArtifactTransform(buildOperation.details, finishEvent)
        } catch (error: LinkageError) {
            logger.debug("Tuist: Build operation is unavailable on this Gradle version", error)
        } catch (error: Exception) {
            logger.debug("Tuist: Could not capture build operation", error)
        }
    }

    private fun recordConfigurationOperation(details: Any?, finishEvent: OperationFinishEvent) {
        val durationMs = finishEvent.endTime - finishEvent.startTime
        val startedAt = formatTimestamp(finishEvent.startTime)

        val operation = when (details) {
            is ConfigureBuildBuildOperationType.Details -> ConfigurationOperationReportEntry(
                phase = "build",
                buildPath = details.buildPath,
                durationMs = durationMs,
                startedAt = startedAt
            )
            is EvaluateSettingsBuildOperationType.Details -> ConfigurationOperationReportEntry(
                phase = "settings",
                buildPath = details.buildPath,
                durationMs = durationMs,
                startedAt = startedAt
            )
            is ConfigureProjectBuildOperationType.Details -> ConfigurationOperationReportEntry(
                phase = "project",
                buildPath = details.buildPath,
                projectPath = details.projectPath,
                durationMs = durationMs,
                startedAt = startedAt
            )
            else -> null
        }

        operation?.let(configurationOperations::add)
    }

    private fun recordConfigurationCacheMetadata(result: Any?, finishEvent: OperationFinishEvent) {
        when {
            result is ConfigurationCacheLoadBuildOperationType.Result -> {
                configurationCacheStatus = "reused"
                configurationCacheEntrySize = result.cacheEntrySize
                configurationCacheLoadDurationMs = finishEvent.endTime - finishEvent.startTime
            }
            result is ConfigurationCacheCheckFingerprintBuildOperationType.Result -> {
                configurationCacheStatus = result.status.name.lowercase()
                result.buildInvalidationReasons
                    .flatMap { it.invalidationReasons }
                    .map { it.message }
                    .forEach(configurationCacheInvalidationReasons::add)
                result.projectInvalidationReasons
                    .flatMap { it.invalidationReasons }
                    .map { it.message }
                    .forEach(configurationCacheInvalidationReasons::add)
            }
        }
    }

    private fun recordArtifactTransform(details: Any?, finishEvent: OperationFinishEvent) {
        if (details !is ExecutePlannedTransformStepBuildOperationType.Details) return

        val identity = details.plannedTransformStepIdentity
        artifactTransforms.add(
            ArtifactTransformReportEntry(
                transformerName = details.transformerName,
                transformActionClass = details.transformActionClass.name,
                subjectName = details.subjectName,
                artifactName = identity.artifactName,
                consumerProjectPath = identity.consumerProjectPath,
                durationMs = finishEvent.endTime - finishEvent.startTime,
                startedAt = formatTimestamp(finishEvent.startTime)
            )
        )
    }

    private fun configurationCacheReport(): ConfigurationCacheReport? {
        val status = configurationCacheStatus ?: return null
        return ConfigurationCacheReport(
            status = status,
            entrySize = configurationCacheEntrySize,
            loadDurationMs = configurationCacheLoadDurationMs,
            invalidationReasons = configurationCacheInvalidationReasons.toList().sorted()
        )
    }

    private fun formatTimestamp(timestampMs: Long): String =
        Instant.ofEpochMilli(timestampMs)
            .atOffset(ZoneOffset.UTC)
            .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)

    override fun close() {
        val machineMetrics = downsample(machineMetricsCollector.stop(), maxCount = 3600)
        val shouldUploadInBackground = uploadInBackground ?: parameters.backgroundUpload.getOrElse(!ciDetector.isCi())

        if (shouldUploadInBackground) {
            logger.lifecycle("Tuist: Uploading build insights in the background...")
            Thread({
                try {
                    sendReport(machineMetrics)
                } catch (e: Exception) {
                    logger.warn("Tuist: Failed to send build insights: ${e.message}")
                }
            }, "tuist-build-insights-upload").apply {
                isDaemon = false
                start()
            }
        } else {
            try {
                sendReport(machineMetrics)
            } catch (e: Exception) {
                logger.warn("Tuist: Failed to send build insights: ${e.message}")
            }
        }
    }

    private fun sendReport(machineMetrics: List<MachineMetricSample>) {
        val projectValue = parameters.project.orNull
        val httpClients = TuistHttpClients(useEnvironmentProxy = parameters.useEnvironmentProxy.get())
        val projectDir = parameters.projectDir.asFile.get()

        val configProvider = DefaultConfigurationProvider(
            project = projectValue,
            serverUrl = parameters.url.get(),
            projectDir = projectDir,
            httpClients = httpClients
        )

        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            httpClients = httpClients,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )

        val totalDurationMs = ((executionTelemetry.lastTaskAt ?: System.currentTimeMillis()) -
            (executionTelemetry.firstEventAt ?: buildStartTime)).coerceAtLeast(0)

        val report = buildReport(
            id = buildId,
            taskOutcomes = executionTelemetry.tasks.toList(),
            buildFailed = false,
            totalDurationMs = totalDurationMs,
            gradleVersion = parameters.gradleVersion.orNull,
            rootProjectName = parameters.rootProjectName.orNull,
            requestedTasks = executionTelemetry.requestedTasks.ifEmpty { parameters.requestedTasks.getOrElse(emptyList()) }.toList(),
            ciDetector = ciDetector,
            gitInfoProvider = reportGitInfoProvider(),
            customMetadata = buildCustomMetadata(
                configuredTags = parameters.customTags.get(),
                configuredValues = parameters.customValues.get()
            ),
            machineMetrics = machineMetrics,
            configurationCache = configurationCacheReport(),
            configurationOperations = configurationOperations.toList(),
            artifactTransforms = artifactTransforms.toList(),
        )

        val response = httpClient.execute { config ->
            val resolvedUrl = ServerUrlResolver.resolve(
                extensionUrl = parameters.url.get(),
                projectDir = projectDir
            )
            val url = URI(resolvedUrl).resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/gradle/builds")
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
                    else -> {
                        val errorBody = try {
                            connection.errorStream?.bufferedReader()?.use { it.readText() }
                        } catch (_: Exception) { null }
                        logger.warn("Tuist: Build insights request failed with HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}")
                        null
                    }
                }
            } finally {
                connection.disconnect()
            }
        }

        if (response != null) {
            logger.lifecycle("Tuist: Build insights reported successfully (build $buildId)")
        } else {
            logger.warn("Tuist: Failed to report build insights.")
        }
    }

    private fun reportGitInfoProvider(): GitInfoProvider =
        gitInfoProvider ?: GitInfo(
            branch = parameters.gitBranch.orNull,
            commitSha = parameters.gitCommitSha.orNull,
            ref = parameters.gitRef.orNull,
            remoteUrlOrigin = parameters.gitRemoteUrlOrigin.orNull
        )
}

internal fun <T> downsample(samples: List<T>, maxCount: Int): List<T> {
    if (samples.size <= maxCount || maxCount < 2) return samples
    val step = (samples.size - 1).toDouble() / (maxCount - 1).toDouble()
    return (0 until maxCount).map { i ->
        samples[minOf((i * step).toInt(), samples.size - 1)]
    }
}

internal fun buildReport(
    id: String,
    taskOutcomes: List<TaskOutcomeData>,
    buildFailed: Boolean,
    totalDurationMs: Long,
    gradleVersion: String? = null,
    rootProjectName: String? = null,
    requestedTasks: List<String> = emptyList(),
    ciDetector: CIDetector = EnvironmentCIDetector(),
    gitInfoProvider: GitInfoProvider = ProcessGitInfoProvider(),
    customMetadata: BuildCustomMetadata = BuildCustomMetadata(),
    machineMetrics: List<MachineMetricSample>? = null,
    configurationCache: ConfigurationCacheReport? = null,
    configurationOperations: List<ConfigurationOperationReportEntry> = emptyList(),
    artifactTransforms: List<ArtifactTransformReportEntry> = emptyList()
): BuildReportRequest {
    val status = when {
        buildFailed -> "failure"
        taskOutcomes.any { it.outcome == TaskOutcome.FAILED } -> "failure"
        else -> "success"
    }

    return BuildReportRequest(
        id = id,
        durationMs = totalDurationMs,
        status = status,
        gradleVersion = gradleVersion,
        javaVersion = System.getProperty("java.version"),
        isCi = ciDetector.isCi(),
        gitBranch = gitInfoProvider.branch(),
        gitCommitSha = gitInfoProvider.commitSha(),
        gitRef = gitInfoProvider.ref(),
        gitRemoteUrlOrigin = gitInfoProvider.remoteUrlOrigin(),
        rootProjectName = rootProjectName,
        requestedTasks = requestedTasks,
        tasks = taskOutcomes.map { task ->
            TaskReportEntry(
                taskPath = task.taskPath,
                outcome = task.outcome,
                cacheable = task.cacheable,
                durationMs = task.durationMs,
                cacheKey = task.cacheKey,
                cacheArtifactSize = task.cacheArtifactSize,
                startedAt = task.startedAt,
                remoteCacheMiss = task.remoteCacheMiss,
                remoteCacheStored = task.remoteCacheStored,
                execution = task.execution
            )
        },
        customMetadata = customMetadata,
        machineMetrics = machineMetrics,
        configurationCache = configurationCache,
        configurationOperations = configurationOperations,
        artifactTransforms = artifactTransforms
    )
}

internal abstract class TuistBuildInsightsPlugin @Inject constructor(
    private val eventsListenerRegistry: BuildEventsListenerRegistry
) : Plugin<Project> {
    private val logger = Logging.getLogger(TuistBuildInsightsPlugin::class.java)

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return
        val gitInfo = project.providers.of(GitInfoValueSource::class.java) {}.get()

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistBuildInsights",
            TuistBuildInsightsService::class.java
        ) {
            parameters.url.set(config.url)
            config.project?.let { parameters.project.set(it) }
            parameters.useEnvironmentProxy.set(config.network.proxy)
            parameters.gradleVersion.set(project.gradle.gradleVersion)
            parameters.rootProjectName.set(project.rootProject.name)
            parameters.projectDir.set(project.rootProject.layout.projectDirectory)
            parameters.customTags.set(config.customMetadata.tags)
            parameters.customValues.set(config.customMetadata.values)
            parameters.gitBranch.set(gitInfo.branch())
            parameters.gitCommitSha.set(gitInfo.commitSha())
            parameters.gitRef.set(gitInfo.ref())
            parameters.gitRemoteUrlOrigin.set(gitInfo.remoteUrlOrigin())
            parameters.requestedTasks.set(project.gradle.startParameter.taskRequests.flatMap { it.args })
            parameters.backgroundUpload.set(config.uploadInBackground ?: !EnvironmentCIDetector().isCi())
        }

        // A provider can have only one subscription. An operation-only service also
        // restores the operation subscription when Gradle reuses configuration.
        try {
            (eventsListenerRegistry as BuildEventListenerRegistryInternal).onOperationCompletion(serviceProvider)
        } catch (error: LinkageError) {
            logger.warn("Tuist: Detailed build telemetry is unavailable on this Gradle version.")
        } catch (error: Exception) {
            logger.warn("Tuist: Detailed build telemetry is unavailable on this Gradle version.")
        }
    }
}

internal abstract class MetricsInputTracking @Inject constructor(val state: InputTrackingState)
