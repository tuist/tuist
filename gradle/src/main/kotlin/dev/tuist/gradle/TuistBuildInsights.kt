package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.provider.Property
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.api.tasks.CacheableTask
import org.gradle.build.event.BuildEventsListenerRegistry
import org.gradle.tooling.events.FinishEvent
import org.gradle.tooling.events.OperationCompletionListener
import org.gradle.tooling.events.task.TaskFinishEvent
import org.gradle.tooling.events.task.TaskFailureResult
import org.gradle.tooling.events.task.TaskSkippedResult
import org.gradle.tooling.events.task.TaskSuccessResult
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.ConcurrentLinkedQueue
import javax.inject.Inject

// --- Data classes ---

data class TaskOutcomeData(
    val taskPath: String,
    val outcome: String,
    val cacheable: Boolean,
    val durationMs: Long,
    val taskType: String?
)

data class TaskReportEntry(
    @SerializedName("task_path") val taskPath: String,
    val outcome: String,
    val cacheable: Boolean,
    @SerializedName("duration_ms") val durationMs: Long,
    @SerializedName("task_type") val taskType: String?
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
    @SerializedName("avoidance_savings_ms") val avoidanceSavingsMs: Long,
    val tasks: List<TaskReportEntry>
)

data class BuildReportResponse(val id: String)

// --- HTTP Client ---

interface BuildInsightsHttpClient {
    fun postBuildReport(url: URI, token: String, report: BuildReportRequest): BuildReportResponse?
}

class DefaultBuildInsightsHttpClient : BuildInsightsHttpClient {
    private val gson = Gson()

    override fun postBuildReport(url: URI, token: String, report: BuildReportRequest): BuildReportResponse? {
        val connection = url.toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $token")

            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                gson.toJson(report, writer)
            }

            return when (connection.responseCode) {
                HttpURLConnection.HTTP_CREATED -> {
                    BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                        gson.fromJson(reader, BuildReportResponse::class.java)
                    }
                }
                else -> null
            }
        } finally {
            connection.disconnect()
        }
    }
}

// --- CI Detection ---

object CIDetector {
    fun isCi(): Boolean {
        return System.getenv("CI") != null ||
            System.getenv("JENKINS_URL") != null ||
            System.getenv("GITHUB_ACTIONS") != null ||
            System.getenv("GITLAB_CI") != null ||
            System.getenv("CIRCLECI") != null ||
            System.getenv("BITBUCKET_BUILD_NUMBER") != null ||
            System.getenv("BUILDKITE") != null ||
            System.getenv("TRAVIS") != null ||
            System.getenv("TF_BUILD") != null
    }
}

// --- Git Info ---

object GitInfo {
    fun branch(): String? = runGitCommand("rev-parse", "--abbrev-ref", "HEAD")
    fun commitSha(): String? = runGitCommand("rev-parse", "HEAD")
    fun ref(): String? = runGitCommand("describe", "--tags", "--always")

    private fun runGitCommand(vararg args: String): String? {
        return try {
            val process = ProcessBuilder(listOf("git") + args)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().readLine()?.trim()
            val exitCode = process.waitFor()
            if (exitCode == 0 && !output.isNullOrBlank()) output else null
        } catch (e: Exception) {
            null
        }
    }
}

// --- Build Service ---

abstract class TuistBuildInsightsService :
    BuildService<TuistBuildInsightsService.Params>,
    OperationCompletionListener,
    AutoCloseable {

    interface Params : BuildServiceParameters {
        val serverUrl: Property<String>
        val fullHandle: Property<String>
        val executablePath: Property<String>
        val gradleVersion: Property<String>
        val rootProjectName: Property<String>
    }

    private val taskOutcomes = ConcurrentLinkedQueue<TaskOutcomeData>()
    private val cacheableTaskPaths = mutableSetOf<String>()
    private var buildStartTime: Long = System.currentTimeMillis()
    private var buildFailed = false

    fun setCacheableTasks(paths: Set<String>) {
        cacheableTaskPaths.addAll(paths)
    }

    override fun onFinish(event: FinishEvent) {
        if (event !is TaskFinishEvent) return
        val result = event.result
        val taskPath = event.descriptor.taskPath
        val durationMs = result.endTime - result.startTime

        val (outcome, cacheable) = when (result) {
            is TaskSuccessResult -> {
                when {
                    result.isFromCache -> "from_cache" to true
                    result.isUpToDate -> "up_to_date" to cacheableTaskPaths.contains(taskPath)
                    else -> "executed" to cacheableTaskPaths.contains(taskPath)
                }
            }
            is TaskFailureResult -> {
                buildFailed = true
                "failed" to cacheableTaskPaths.contains(taskPath)
            }
            is TaskSkippedResult -> {
                val skipMessage = result.skipMessage ?: ""
                val outcomeStr = if (skipMessage.contains("NO-SOURCE", ignoreCase = true)) "no_source" else "skipped"
                outcomeStr to false
            }
            else -> "executed" to false
        }

        taskOutcomes.add(
            TaskOutcomeData(
                taskPath = taskPath,
                outcome = outcome,
                cacheable = cacheable,
                durationMs = durationMs,
                taskType = null
            )
        )
    }

    override fun close() {
        try {
            sendReport()
        } catch (e: Exception) {
            println("Tuist: Warning - Failed to send build insights: ${e.message}")
        }
    }

    private fun sendReport() {
        val fullHandle = parameters.fullHandle.get()
        val parts = fullHandle.split("/")
        if (parts.size != 2) {
            println("Tuist: Warning - Invalid fullHandle format for build insights: $fullHandle")
            return
        }
        val (accountHandle, projectHandle) = parts

        val configProvider = TuistCommandConfigurationProvider(
            fullHandle = fullHandle,
            command = listOf(parameters.executablePath.orNull ?: "tuist"),
            serverUrl = parameters.serverUrl.get()
        )

        val config = configProvider.getConfiguration()
        if (config == null) {
            println("Tuist: Warning - Could not get configuration for build insights. Skipping report.")
            return
        }

        val tasks = taskOutcomes.toList()
        val totalDurationMs = System.currentTimeMillis() - buildStartTime

        val avoidanceSavingsMs = tasks
            .filter { it.outcome == "from_cache" || it.outcome == "up_to_date" }
            .sumOf { it.durationMs }

        val status = when {
            buildFailed -> "failure"
            tasks.any { it.outcome == "failed" } -> "failure"
            else -> "success"
        }

        val report = BuildReportRequest(
            durationMs = totalDurationMs,
            status = status,
            gradleVersion = parameters.gradleVersion.orNull,
            javaVersion = System.getProperty("java.version"),
            isCi = CIDetector.isCi(),
            gitBranch = GitInfo.branch(),
            gitCommitSha = GitInfo.commitSha(),
            gitRef = GitInfo.ref(),
            rootProjectName = parameters.rootProjectName.orNull,
            avoidanceSavingsMs = avoidanceSavingsMs,
            tasks = tasks.map { task ->
                TaskReportEntry(
                    taskPath = task.taskPath,
                    outcome = task.outcome,
                    cacheable = task.cacheable,
                    durationMs = task.durationMs,
                    taskType = task.taskType
                )
            }
        )

        val serverUrl = parameters.serverUrl.get().trimEnd('/')
        val url = URI("$serverUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")

        val httpClient: BuildInsightsHttpClient = DefaultBuildInsightsHttpClient()
        val response = httpClient.postBuildReport(url, config.token, report)

        if (response != null) {
            println("Tuist: Build insights reported successfully (build ${response.id})")
        } else {
            println("Tuist: Warning - Failed to report build insights.")
        }
    }
}

// --- Project Plugin ---

internal abstract class TuistBuildInsightsPlugin @Inject constructor(
    private val eventsListenerRegistry: BuildEventsListenerRegistry
) : Plugin<Project> {

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val serverUrl = project.findProperty("tuist.serverUrl") as? String ?: "https://tuist.dev"
        val fullHandle = project.findProperty("tuist.fullHandle") as? String ?: ""
        val executablePath = project.findProperty("tuist.executablePath") as? String ?: "tuist"
        val gradleVersion = project.gradle.gradleVersion

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistBuildInsights",
            TuistBuildInsightsService::class.java
        ) {
            parameters.serverUrl.set(serverUrl)
            parameters.fullHandle.set(fullHandle)
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
            serviceProvider.get().setCacheableTasks(cacheablePaths)
        }
    }
}
