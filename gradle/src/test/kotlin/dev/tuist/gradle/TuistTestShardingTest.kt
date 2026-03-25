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

class TuistTestShardingServiceTest {

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
            testSuites = listOf("com.example.LoginTest", "com.example.SignupTest"),
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
    }

    @Test
    fun `createShardPlan throws on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        assertThrows<org.gradle.api.GradleException> {
            service.createShardPlan(
                reference = "plan-1",
                testSuites = listOf("com.example.Test"),
                shardMax = 2,
                shardMin = null,
                shardMaxDuration = null
            )
        }
    }

    @Test
    fun `getShard returns shard with modules and suites`() {
        val service = createService()

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(Gson().toJson(
            Shard(
                modules = listOf("AppModule"),
                shardPlanId = java.util.UUID.randomUUID(),
                suites = mapOf("AppModule" to listOf("com.example.LoginTest", "com.example.LogoutTest")),
                downloadUrl = "https://download.example.com/bundle.zip"
            )
        )))

        val result = service.getShard("plan-1", 0)

        assertEquals(listOf("AppModule"), result.modules)
        assertEquals(listOf("com.example.LoginTest", "com.example.LogoutTest"), result.suites["AppModule"])
    }

    @Test
    fun `getShard throws on not found`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        assertThrows<org.gradle.api.GradleException> {
            service.getShard("nonexistent", 0)
        }
    }
}

class DeriveReferenceTest {

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
}

class DetectCIProviderTest {

    private fun envWith(vararg pairs: Pair<String, String>): EnvironmentProvider {
        val map = pairs.toMap()
        return EnvironmentProvider { name -> map[name] }
    }

    @Test
    fun `returns null for empty environment`() {
        assertNull(detectCIProvider(envWith()))
    }

    @Test
    fun `detects GitHub Actions`() {
        assertEquals(CIProvider.GITHUB, detectCIProvider(envWith("GITHUB_ACTIONS" to "true")))
    }

    @Test
    fun `detects GitLab CI`() {
        assertEquals(CIProvider.GITLAB, detectCIProvider(envWith("GITLAB_CI" to "true")))
    }

    @Test
    fun `detects CircleCI`() {
        assertEquals(CIProvider.CIRCLECI, detectCIProvider(envWith("CIRCLECI" to "true")))
    }

    @Test
    fun `detects Buildkite`() {
        assertEquals(CIProvider.BUILDKITE, detectCIProvider(envWith("BUILDKITE" to "true")))
    }

    @Test
    fun `detects Codemagic`() {
        assertEquals(CIProvider.CODEMAGIC, detectCIProvider(envWith("CM_BUILD_ID" to "123")))
    }

    @Test
    fun `detects Bitrise`() {
        assertEquals(CIProvider.BITRISE, detectCIProvider(envWith("BITRISE_IO" to "true")))
    }
}

class WriteShardMatrixOutputTest {

    private fun createTask(projectDir: File): TuistPrepareTestShardsTask {
        val project = org.gradle.testfixtures.ProjectBuilder.builder()
            .withProjectDir(projectDir)
            .build()
        return project.tasks.create("testShards", TuistPrepareTestShardsTask::class.java)
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

    @Test
    fun `github writes matrix to output file`(@TempDir tempDir: File) {
        val githubOutputFile = File(tempDir, "github_output").apply { writeText("") }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1, 2), "test-ref", shardPlan(3), CIProvider.GITHUB,
            envWith("GITHUB_OUTPUT" to githubOutputFile.absolutePath)
        )

        assertEquals("""matrix={"shard":[0, 1, 2]}""" + "\n", githubOutputFile.readText())
    }

    @Test
    fun `gitlab writes child pipeline yml`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), CIProvider.GITLAB)

        assertEquals(
            """
            shard-0:
              extends: .tuist-shard
              variables:
                TUIST_SHARD_INDEX: "0"

            shard-1:
              extends: .tuist-shard
              variables:
                TUIST_SHARD_INDEX: "1"

            """.trimIndent() + "\n",
            File(tempDir, ".tuist-shard-child-pipeline.yml").readText()
        )
    }

    @Test
    fun `circleci writes continuation json`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), CIProvider.CIRCLECI)

        assertEquals(
            """{"shard-indices":"0,1","shard-count":2}""",
            File(tempDir, ".tuist-shard-continuation.json").readText()
        )
    }

    @Test
    fun `buildkite writes pipeline yml`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), CIProvider.BUILDKITE)

        assertEquals(
            """
            steps:
              - label: "Shard #0"
                env:
                  TUIST_SHARD_INDEX: "0"

              - label: "Shard #1"
                env:
                  TUIST_SHARD_INDEX: "1"

            """.trimIndent() + "\n",
            File(tempDir, ".tuist-shard-pipeline.yml").readText()
        )
    }

    @Test
    fun `codemagic writes to cm env file`(@TempDir tempDir: File) {
        val cmEnvFile = File(tempDir, "cm_env").apply { writeText("") }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1), "test-ref", shardPlan(), CIProvider.CODEMAGIC,
            envWith("CM_ENV" to cmEnvFile.absolutePath)
        )

        assertEquals(
            """TUIST_SHARD_MATRIX={"shard":[0, 1]}""" + "\nTUIST_SHARD_COUNT=2\n",
            cmEnvFile.readText()
        )
    }

    @Test
    fun `bitrise writes to deploy dir`(@TempDir tempDir: File) {
        val deployDir = File(tempDir, "deploy").apply { mkdirs() }
        val task = createTask(tempDir)

        task.writeShardMatrixOutput(
            listOf(0, 1), "test-ref", shardPlan(), CIProvider.BITRISE,
            envWith("BITRISE_DEPLOY_DIR" to deployDir.absolutePath)
        )

        assertEquals(
            """{"shard":[0, 1],"shard_count":2}""",
            File(deployDir, ".tuist-shard-matrix.json").readText()
        )
    }

    @Test
    fun `fallback writes shard matrix json`(@TempDir tempDir: File) {
        val task = createTask(tempDir)
        task.writeShardMatrixOutput(listOf(0, 1), "test-ref", shardPlan(), null)

        assertEquals(
            """{"reference":"test-ref","shard_count":2,"shards":[{"index":0,"test_targets":["com.example.Test0"],"estimated_duration_ms":1000},{"index":1,"test_targets":["com.example.Test1"],"estimated_duration_ms":1000}]}""",
            File(tempDir, ".tuist-shard-matrix.json").readText()
        )
    }
}

class DiscoverTestSuitesTest {

    @Test
    fun `discovers test classes from compiled output`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/SignupTest.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest", "com.example.SignupTest"), suites)
    }

    @Test
    fun `excludes inner classes`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/LoginTest\$Companion.class").createNewFile()
        File(classesDir, "com/example/LoginTest\$nested.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest"), suites)
    }

    @Test
    fun `excludes non-class files`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/README.txt").createNewFile()
        File(classesDir, "com/example/data.json").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest"), suites)
    }

    @Test
    fun `returns empty list for empty directory`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")
        classesDir.mkdirs()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertTrue(suites.isEmpty())
    }

    @Test
    fun `handles multiple class directories`(@TempDir tempDir: File) {
        val dir1 = File(tempDir, "module1/build/classes/kotlin/test")
        val dir2 = File(tempDir, "module2/build/classes/kotlin/test")

        File(dir1, "com/example").mkdirs()
        File(dir1, "com/example/Test1.class").createNewFile()
        File(dir2, "com/other").mkdirs()
        File(dir2, "com/other/Test2.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(dir1, dir2))

        assertEquals(listOf("com.example.Test1", "com.other.Test2"), suites)
    }
}
