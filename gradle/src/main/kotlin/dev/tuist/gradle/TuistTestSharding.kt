package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.CreateShardSessionBody
import dev.tuist.gradle.api.model.ShardAssignmentResponse
import dev.tuist.gradle.api.model.ShardSessionResponse
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.logging.Logging
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

internal abstract class TuistTestShardingPlugin : Plugin<Project> {

    private val logger = Logging.getLogger(TuistTestShardingPlugin::class.java)

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val shardIndexStr = System.getenv("TUIST_SHARD_INDEX") ?: return
        val shardIndex = shardIndexStr.toIntOrNull()
        if (shardIndex == null) {
            logger.warn("Tuist: TUIST_SHARD_INDEX is not a valid integer: $shardIndexStr")
            return
        }

        val config = TuistGradleConfig.from(project) ?: return

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

        val sessionId = shardingService.deriveSessionId()
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
