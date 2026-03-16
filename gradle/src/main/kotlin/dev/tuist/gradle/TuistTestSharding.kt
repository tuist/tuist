package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.CreateShardSessionBody
import dev.tuist.gradle.api.model.ShardAssignmentResponse
import dev.tuist.gradle.api.model.ShardSessionResponse
import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.logging.Logging
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.testing.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI

class TuistTestShardingService(
    private val httpClient: TuistHttpClient,
    private val baseUrl: String
) {
    private val logger = Logging.getLogger(TuistTestShardingService::class.java)

    fun createShardSession(
        sessionId: String,
        testSuites: List<String>,
        shardMax: Int,
        shardMin: Int?,
        shardMaxDuration: Int?
    ): ShardSessionResponse? {
        val body = CreateShardSessionBody(
            sessionId = sessionId,
            testSuites = testSuites,
            shardMin = shardMin,
            shardMax = shardMax,
            shardMaxDuration = shardMaxDuration,
            granularity = "suite"
        )

        return try {
            httpClient.execute { config ->
                val url = URI(baseUrl.trimEnd('/')).resolve(
                    "/api/projects/${config.accountHandle}/${config.projectHandle}/tests/shards"
                )
                val connection = httpClient.openConnection(url, config)
                try {
                    connection.requestMethod = "POST"
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")

                    OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                        Gson().toJson(body, writer)
                    }

                    when (connection.responseCode) {
                        HttpURLConnection.HTTP_OK -> {
                            BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                                Gson().fromJson(reader, ShardSessionResponse::class.java)
                            }
                        }
                        HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                        else -> {
                            val errorBody = try {
                                connection.errorStream?.bufferedReader()?.use { it.readText() }
                            } catch (_: Exception) { null }
                            logger.warn("Tuist: Shard session creation failed with HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}")
                            null
                        }
                    }
                } finally {
                    connection.disconnect()
                }
            }
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to create shard session: ${e.message}")
            null
        }
    }

    fun getShardAssignment(sessionId: String, shardIndex: Int): ShardAssignmentResponse? {
        return try {
            httpClient.execute { config ->
                val url = URI(baseUrl.trimEnd('/')).resolve(
                    "/api/projects/${config.accountHandle}/${config.projectHandle}/tests/shards/$sessionId/$shardIndex"
                )
                val connection = httpClient.openConnection(url, config)
                try {
                    connection.requestMethod = "GET"
                    connection.setRequestProperty("Accept", "application/json")

                    when (connection.responseCode) {
                        HttpURLConnection.HTTP_OK -> {
                            BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                                Gson().fromJson(reader, ShardAssignmentResponse::class.java)
                            }
                        }
                        HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                        else -> {
                            val errorBody = try {
                                connection.errorStream?.bufferedReader()?.use { it.readText() }
                            } catch (_: Exception) { null }
                            logger.warn("Tuist: Shard assignment request failed with HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}")
                            null
                        }
                    }
                } finally {
                    connection.disconnect()
                }
            }
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to get shard assignment: ${e.message}")
            null
        }
    }

    internal fun deriveSessionId(): String? {
        System.getenv("GITHUB_RUN_ID")?.let { runId ->
            val attempt = System.getenv("GITHUB_RUN_ATTEMPT") ?: "1"
            return "github-$runId-$attempt"
        }
        System.getenv("CIRCLE_WORKFLOW_ID")?.let { return "circleci-$it" }
        System.getenv("BUILDKITE_BUILD_ID")?.let { return "buildkite-$it" }
        System.getenv("CI_PIPELINE_ID")?.let { return "gitlab-$it" }
        System.getenv("CM_BUILD_ID")?.let { return "codemagic-$it" }
        return null
    }
}

private val classPattern = Regex("""^\s*class\s+(\w+)""", RegexOption.MULTILINE)

internal fun discoverTestSuites(project: Project): List<String> {
    val testSuites = mutableSetOf<String>()
    for (subproject in project.allprojects) {
        val testDirs = listOf("src/test/java", "src/test/kotlin")
        for (testDir in testDirs) {
            val dir = subproject.file(testDir)
            if (!dir.exists()) continue
            dir.walkTopDown()
                .filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                .forEach { file ->
                    val relativePath = file.relativeTo(dir).path
                    val packagePrefix = relativePath
                        .substringBeforeLast(java.io.File.separatorChar.toString(), "")
                        .replace(java.io.File.separatorChar, '.')
                    val content = file.readText()
                    val classNames = classPattern.findAll(content).map { it.groupValues[1] }.toList()
                    for (className in classNames) {
                        val fqcn = if (packagePrefix.isNotEmpty()) "$packagePrefix.$className" else className
                        testSuites.add(fqcn)
                    }
                }
        }
    }
    return testSuites.sorted()
}

abstract class TuistPrepareTestShardsTask : DefaultTask() {

    @get:Input
    var shardMax: Int = 2

    @get:Input
    @get:Optional
    var shardMin: Int? = null

    @get:Input
    @get:Optional
    var shardMaxDuration: Int? = null

    @get:Input
    @get:Optional
    var sessionIdOverride: String? = null

    @get:Input
    var serverUrl: String = "https://tuist.dev"

    @get:Input
    @get:Optional
    var tuistProject: String? = null

    @TaskAction
    fun execute() {
        val shardingService = createShardingService()

        val sessionId = sessionIdOverride
            ?: shardingService.deriveSessionId()
            ?: throw org.gradle.api.GradleException(
                "Could not derive shard session ID. Set TUIST_SHARD_SESSION_ID or run in a supported CI environment."
            )

        val testSuites = discoverTestSuites(project)
        if (testSuites.isEmpty()) {
            throw org.gradle.api.GradleException("No test suites found. Ensure test source directories contain *Test.kt or *Test.java files.")
        }

        logger.lifecycle("Tuist: Discovered ${testSuites.size} test suite(s): ${testSuites.joinToString(", ")}")

        val response = shardingService.createShardSession(
            sessionId = sessionId,
            testSuites = testSuites,
            shardMax = shardMax,
            shardMin = shardMin,
            shardMaxDuration = shardMaxDuration
        ) ?: throw org.gradle.api.GradleException("Failed to create shard session on the server.")

        logger.lifecycle("Tuist: Shard session created — session=$sessionId, shards=${response.shardCount}")
        for (shard in response.shards) {
            logger.lifecycle("Tuist:   Shard ${shard.index}: ${shard.testTargets.joinToString(", ")} (est. ${shard.estimatedDurationMs}ms)")
        }

        val outputFile = project.layout.buildDirectory.file("tuist/shard-matrix.json").get().asFile
        outputFile.parentFile.mkdirs()
        val matrix = mapOf(
            "session_id" to sessionId,
            "shard_count" to response.shardCount,
            "shards" to response.shards.map { shard ->
                mapOf(
                    "index" to shard.index,
                    "test_targets" to shard.testTargets,
                    "estimated_duration_ms" to shard.estimatedDurationMs
                )
            }
        )
        outputFile.writeText(Gson().toJson(matrix))
        logger.lifecycle("Tuist: Shard matrix written to ${outputFile.path}")
    }

    private fun createShardingService(): TuistTestShardingService {
        val configProvider = DefaultConfigurationProvider(
            project = tuistProject,
            serverUrl = serverUrl,
            projectDir = project.rootDir
        )
        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
        return TuistTestShardingService(httpClient = httpClient, baseUrl = serverUrl)
    }
}

internal abstract class TuistTestShardingPlugin : Plugin<Project> {

    private val logger = Logging.getLogger(TuistTestShardingPlugin::class.java)

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return

        project.tasks.register("tuistPrepareTestShards", TuistPrepareTestShardsTask::class.java).configure {
            group = "tuist"
            description = "Discover test suites and create a shard session on the Tuist server"
            serverUrl = config.url
            tuistProject = config.project

            project.findProperty("tuistShardMax")?.toString()?.toIntOrNull()?.let { shardMax = it }
            project.findProperty("tuistShardMin")?.toString()?.toIntOrNull()?.let { shardMin = it }
            project.findProperty("tuistShardMaxDuration")?.toString()?.toIntOrNull()?.let { shardMaxDuration = it }

            System.getenv("TUIST_SHARD_SESSION_ID")?.let { sessionIdOverride = it }
        }

        val shardIndexStr = System.getenv("TUIST_SHARD_INDEX") ?: return
        val shardIndex = shardIndexStr.toIntOrNull()
        if (shardIndex == null) {
            logger.warn("Tuist: TUIST_SHARD_INDEX is not a valid integer: $shardIndexStr")
            return
        }

        val configProvider = DefaultConfigurationProvider(
            project = config.project,
            serverUrl = config.url,
            projectDir = java.io.File(System.getProperty("user.dir"))
        )
        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
        val shardingService = TuistTestShardingService(httpClient = httpClient, baseUrl = config.url)

        val sessionId = System.getenv("TUIST_SHARD_SESSION_ID") ?: shardingService.deriveSessionId()
        if (sessionId == null) {
            logger.warn("Tuist: Could not derive shard session ID, skipping test sharding")
            return
        }

        logger.lifecycle("Tuist: Test sharding active — shard index $shardIndex, session $sessionId")

        val assignment = shardingService.getShardAssignment(sessionId, shardIndex)
        if (assignment == null) {
            logger.warn("Tuist: Failed to get shard assignment, running all tests")
            return
        }

        val assignedTargets = assignment.testTargets
        logger.lifecycle("Tuist: Shard $shardIndex assigned ${assignedTargets.size} test suite(s)")

        project.allprojects {
            val subproject = this
            subproject.tasks.withType(Test::class.java).configureEach {
                val testTask = this
                testTask.doFirst {
                    testTask.filter.isFailOnNoMatchingTests = false
                    for (target in assignedTargets) {
                        testTask.filter.includeTestsMatching(target)
                    }
                    logger.lifecycle("Tuist: Applied shard filter to test task '${testTask.path}' with ${assignedTargets.size} suite(s)")
                }
            }
        }
    }
}
