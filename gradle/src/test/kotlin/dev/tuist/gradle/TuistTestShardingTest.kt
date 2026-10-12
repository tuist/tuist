package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.Shard
import dev.tuist.gradle.api.model.ShardPlan
import dev.tuist.gradle.api.model.ShardPlanShardsInner
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistTestShardingTest {

    private lateinit var mockWebServer: MockWebServer

    @BeforeEach
    fun setup() {
        mockWebServer = MockWebServer()
        mockWebServer.start()
    }

    @AfterEach
    fun tearDown() {
        mockWebServer.shutdown()
    }

    private fun createService(): TuistTestShardingService {
        val baseUrl = mockWebServer.url("/").toString().trimEnd('/')
        return TuistTestShardingService(
            baseUrl = baseUrl,
            token = "test-token",
            accountHandle = "test-account",
            projectHandle = "test-project"
        )
    }

    private fun createTask(projectDir: File): TuistPrepareTestShardsTask {
        val project = org.gradle.testfixtures.ProjectBuilder.builder()
            .withProjectDir(projectDir)
            .build()
        return project.tasks.register("testShards", TuistPrepareTestShardsTask::class.java) {
            outputDirectory.set(project.layout.projectDirectory)
        }.get()
    }

    private fun shardPlan(shardCount: Int = 2) = ShardPlan(
        reference = "test-ref",
        shardCount = shardCount,
        shards = (0 until shardCount).map { index ->
            ShardPlanShardsInner(
                index = index,
                testTargets = listOf("com.example.Test$index"),
                estimatedDurationMs = 1000
            )
        },
        id = java.util.UUID.fromString("00000000-0000-0000-0000-000000000000")
    )

    private fun envWith(vararg pairs: Pair<String, String>): EnvironmentProvider {
        val map = pairs.toMap()
        return EnvironmentProvider { name -> map[name] }
    }

    // MARK: - createShardPlan

    @Test
    fun `createShardPlan sends correct request and parses response`() {
        val service = createService()

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(Gson().toJson(
            ShardPlan(
                reference = "github-123-1",
                shardCount = 2,
                shards = listOf(
                    ShardPlanShardsInner(index = 0, testTargets = listOf("com.example.LoginTest"), estimatedDurationMs = 5000),
                    ShardPlanShardsInner(index = 1, testTargets = listOf("com.example.SignupTest"), estimatedDurationMs = 4500)
                ),
                id = java.util.UUID.randomUUID()
            )
        )))

        val result = service.createShardPlan(
            reference = "github-123-1",
            modules = listOf(":app", ":lib"),
            gitBranch = "feature",
            shardMax = 2,
            shardMin = null,
            shardMaxDuration = null
        )

        assertEquals(2, result.shardCount)
        assertEquals("com.example.LoginTest", result.shards[0].testTargets[0])

        val request = mockWebServer.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.endsWith("/api/projects/test-account/test-project/tests/shards"))
        assertTrue(request.getHeader("Authorization") == "Bearer test-token")
        val body = parseJson(request.body.readUtf8())
        assertEquals(listOf(":app", ":lib"), body["modules"])
        assertEquals("suite", body["granularity"])
        assertEquals("feature", body["git_branch"])
        assertNull(body["test_suites"])
    }

    @Test
    fun `createShardPlan throws on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        assertThrows<org.gradle.api.GradleException> {
            service.createShardPlan(
                reference = "plan-1",
                modules = listOf(":app"),
                gitBranch = null,
                shardMax = 2,
                shardMin = null,
                shardMaxDuration = null
            )
        }
    }

    // MARK: - getShard

    @Test
    fun `getShard returns shard with modules and suites`() {
        val service = TuistTestShardingService(
            baseUrl = mockWebServer.url("/").toString().trimEnd('/'),
            token = "test-token",
            accountHandle = "test-account",
            projectHandle = "test-project",
            httpClients = TuistHttpClients(pluginVersion = "0.17.0")
        )

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(Gson().toJson(
            Shard(
                modules = listOf("AppModule"),
                shardPlanId = java.util.UUID.randomUUID(),
                suites = mapOf("AppModule" to listOf("com.example.LoginTest", "com.example.LogoutTest")),
                downloadUrls = emptyList()
            )
        )))

        val result = service.getShard("plan-1", 0)

        assertEquals(listOf("AppModule"), result.modules)
        assertEquals(listOf("com.example.LoginTest", "com.example.LogoutTest"), result.suites["AppModule"])
        assertEquals("0.17.0", mockWebServer.takeRequest().getHeader(PluginVersion.HEADER_NAME))
    }

    @Test
    fun `getShard throws on not found`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        assertThrows<org.gradle.api.GradleException> {
            service.getShard("nonexistent", 0)
        }
    }

    // MARK: - deriveReference

    @Test
    fun `deriveReference returns null without CI environment`() {
        val service = TuistTestShardingService(
            baseUrl = "http://localhost",
            token = "token",
            accountHandle = "account",
            projectHandle = "project"
        )
        if (System.getenv("GITHUB_RUN_ID") == null &&
            System.getenv("CIRCLE_WORKFLOW_ID") == null &&
            System.getenv("BUILDKITE_BUILD_ID") == null &&
            System.getenv("CI_PIPELINE_ID") == null &&
            System.getenv("CM_BUILD_ID") == null
        ) {
            assertNull(service.deriveReference())
        }
    }

    // MARK: - writeShardMatrixOutput

    @Suppress("UNCHECKED_CAST")
    private fun parseJson(content: String): Map<String, Any> =
        Gson().fromJson(content, Map::class.java) as Map<String, Any>

    @Suppress("UNCHECKED_CAST")
    private fun parseJsonList(content: String): List<Any> =
        Gson().fromJson(content, List::class.java) as List<Any>

    @Test
    fun `writeShardMatrixOutput writes GitHub Actions matrix to output file`(@TempDir tempDir: File) {
        val githubOutputFile = File(tempDir, "github_output").apply { writeText("") }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1, 2), "test-ref", shardPlan(3),
            envWith("GITHUB_ACTIONS" to "true", "GITHUB_OUTPUT" to githubOutputFile.absolutePath)
        )

        val line = githubOutputFile.readText().trim()
        assertTrue(line.startsWith("matrix="))
        val json = parseJson(line.removePrefix("matrix="))
        assertEquals(listOf(0.0, 1.0, 2.0), json["shard"])
    }

    @Test
    fun `writeShardMatrixOutput writes GitLab CI child pipeline yml`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), envWith("GITLAB_CI" to "true"))

        val content = File(tempDir, ".tuist-shard-child-pipeline.yml").readText()
        assertTrue(content.contains("shard-0:"))
        assertTrue(content.contains("shard-1:"))
        assertTrue(content.contains("extends: .tuist-shard"))
        assertTrue(content.contains("TUIST_SHARD_INDEX: \"0\""))
        assertTrue(content.contains("TUIST_SHARD_INDEX: \"1\""))
    }

    @Test
    fun `writeShardMatrixOutput writes CircleCI continuation json`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), envWith("CIRCLECI" to "true"))

        val json = parseJson(File(tempDir, ".tuist-shard-continuation.json").readText())
        assertEquals("0,1", json["shard-indices"])
        assertEquals(2.0, json["shard-count"])
    }

    @Test
    fun `writeShardMatrixOutput writes Buildkite pipeline yml`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), envWith("BUILDKITE" to "true"))

        val content = File(tempDir, ".tuist-shard-pipeline.yml").readText()
        assertTrue(content.contains("steps:"))
        assertTrue(content.contains("label: \"Shard #0\""))
        assertTrue(content.contains("label: \"Shard #1\""))
        assertTrue(content.contains("TUIST_SHARD_INDEX: \"0\""))
        assertTrue(content.contains("TUIST_SHARD_INDEX: \"1\""))
    }

    @Test
    fun `writeShardMatrixOutput writes Codemagic env vars to CM_ENV file`(@TempDir tempDir: File) {
        val cmEnvFile = File(tempDir, "cm_env").apply { writeText("") }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1), "test-ref", shardPlan(),
            envWith("CM_BUILD_ID" to "123", "CM_ENV" to cmEnvFile.absolutePath)
        )

        val lines = cmEnvFile.readLines()
        val matrixLine = lines.first { it.startsWith("TUIST_SHARD_MATRIX=") }
        val matrixJson = parseJson(matrixLine.removePrefix("TUIST_SHARD_MATRIX="))
        assertEquals(listOf(0.0, 1.0), matrixJson["shard"])
        assertTrue(lines.any { it == "TUIST_SHARD_COUNT=2" })
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun `writeShardMatrixOutput writes Bitrise matrix to deploy dir`(@TempDir tempDir: File) {
        val deployDir = File(tempDir, "deploy").apply { mkdirs() }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1), "test-ref", shardPlan(),
            envWith("BITRISE_IO" to "true", "BITRISE_DEPLOY_DIR" to deployDir.absolutePath)
        )

        val json = parseJson(File(deployDir, ".tuist-shard-matrix.json").readText())
        assertEquals(listOf(0.0, 1.0), json["shard"])
        assertEquals(2.0, json["shard_count"])
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun `writeShardMatrixOutput writes fallback json when no CI detected`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), envWith())

        val json = parseJson(File(tempDir, ".tuist-shard-matrix.json").readText())
        assertEquals("test-ref", json["reference"])
        assertEquals(2.0, json["shard_count"])
        val shards = json["shards"] as List<Map<String, Any>>
        assertEquals(2, shards.size)
        assertEquals(0.0, shards[0]["index"])
        assertEquals(listOf("com.example.Test0"), shards[0]["test_targets"])
        assertEquals(1.0, shards[1]["index"])
        assertEquals(listOf("com.example.Test1"), shards[1]["test_targets"])
    }
}
