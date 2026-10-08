package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import dev.tuist.gradle.api.model.ShardPlan
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TuistPrepareTestShardsFunctionalTest {

    @TempDir
    lateinit var projectDir: File

    private lateinit var server: MockWebServer
    private val shardPlanRequests = CopyOnWriteArrayList<String>()

    @BeforeEach
    fun setUp() {
        server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val path = request.path.orEmpty()
                return when {
                    path.contains("/api/cache/endpoints") ->
                        MockResponse().setResponseCode(200)
                            .setBody("""{"endpoints":["${server.url("/").toString().trimEnd('/')}"]}""")
                    path.endsWith("/tests/shards") -> {
                        shardPlanRequests.add(request.body.readUtf8())
                        MockResponse().setResponseCode(200).setBody(
                            Gson().toJson(
                                ShardPlan(
                                    reference = "shard-reference",
                                    shardCount = 1,
                                    shards = emptyList(),
                                    id = java.util.UUID.randomUUID()
                                )
                            )
                        )
                    }
                    else -> MockResponse().setResponseCode(200).setBody("{}")
                }
            }
        }
        server.start()
        writeProject()
    }

    @AfterEach
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun `plans every project with a test task without compiling test classes`() {
        val result = runner("tuistPrepareTestShards").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":tuistPrepareTestShards")?.outcome, result.output)
        assertEquals(emptyList(), executedCompileTasks(result), result.output)
        assertEquals(listOf(":app", ":lib"), plannedModules())
        assertEquals("suite", shardPlanRequest().get("granularity").asString)
        assertFalse(shardPlanRequest().has("test_suites"), shardPlanRequests.single())
    }

    @Test
    fun `only plans the projects with the test task selected with tuistShardTestTask`() {
        val result = runner("tuistPrepareTestShards", "-PtuistShardTestTask=otherTest").build()

        assertEquals(emptyList(), executedCompileTasks(result), result.output)
        assertEquals(listOf(":app"), plannedModules())
    }

    @Test
    fun `plans the root project by its name`() {
        File(projectDir, "build.gradle.kts").writeText("plugins {\n    java\n}\n")

        runner("tuistPrepareTestShards", "-PtuistShardTestTask=test").build()

        assertEquals(listOf(":app", ":lib", "sharding-fixture"), plannedModules())
    }

    @Test
    fun `sends the git branch the tests are built from`() {
        git("init", "--initial-branch=sharding-branch")
        git("-c", "user.email=tuist@example.com", "-c", "user.name=Tuist", "commit", "--allow-empty", "-m", "Initial")

        runner("tuistPrepareTestShards").build()

        assertEquals("sharding-branch", shardPlanRequest().get("git_branch").asString)
    }

    @Test
    fun `configures subprojects when invoked by path with configuration on demand`() {
        enableConfigurationOnDemand()

        val result = runner(":tuistPrepareTestShards").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":tuistPrepareTestShards")?.outcome, result.output)
        assertTrue(result.output.contains("Configured :docs"), result.output)
        assertEquals(listOf(":app", ":lib"), plannedModules())
    }

    @Test
    fun `finds the selected test task when invoked by path with configuration on demand`() {
        enableConfigurationOnDemand()

        runner(":tuistPrepareTestShards", "-PtuistShardTestTask=otherTest").build()

        assertEquals(listOf(":app"), plannedModules())
    }

    @Test
    fun `leaves unrelated projects unconfigured with configuration on demand when sharding is not requested`() {
        enableConfigurationOnDemand()

        val result = runner(":app:compileTestJava").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileTestJava")?.outcome, result.output)
        assertFalse(result.output.contains("Configured :docs"), result.output)
    }

    @Test
    fun `plans the shards when the configuration cache is stored and reused`() {
        val stored = runner("tuistPrepareTestShards", "--configuration-cache").build()
        val reused = runner("tuistPrepareTestShards", "--configuration-cache").build()

        assertTrue(stored.output.contains("Configuration cache entry stored"), stored.output)
        assertTrue(reused.output.contains("Configuration cache entry reused"), reused.output)
        assertEquals(TaskOutcome.SUCCESS, reused.task(":tuistPrepareTestShards")?.outcome, reused.output)
        val requests = shardPlanRequests.map { JsonParser.parseString(it).asJsonObject }
        assertEquals(2, requests.size)
        requests.forEach { request ->
            assertEquals(listOf(":app", ":lib"), request.getAsJsonArray("modules").map { it.asString })
            assertTrue(request.has("gradle_build_id"), request.toString())
        }
        assertTrue(requests[0].get("gradle_build_id") != requests[1].get("gradle_build_id"), requests.toString())
        assertTrue(File(projectDir, ".tuist-shard-matrix.json").exists())
    }

    @Test
    fun `fails when no project has the selected test task`() {
        val result = runner("tuistPrepareTestShards", "-PtuistShardTestTask=missingTest").buildAndFail()

        assert(result.output.contains("No test task named 'missingTest'")) { result.output }
    }

    private fun enableConfigurationOnDemand() {
        File(projectDir, "gradle.properties").writeText("org.gradle.configureondemand=true\n")
    }

    private fun executedCompileTasks(result: BuildResult): List<String> =
        result.tasks.map { it.path }.filter { it.substringAfterLast(":").startsWith("compile") }

    private fun shardPlanRequest(): JsonObject = JsonParser.parseString(shardPlanRequests.single()).asJsonObject

    private fun plannedModules(): List<String> = shardPlanRequest().getAsJsonArray("modules").map { it.asString }

    private fun git(vararg arguments: String) {
        val process = ProcessBuilder(listOf("git") + arguments).directory(projectDir).redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().readText()
        check(process.waitFor() == 0) { output }
    }

    private fun runner(vararg arguments: String): GradleRunner =
        GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments(*arguments, "--stacktrace")
            .withPluginClasspath()
            .withEnvironment(
                System.getenv().filterKeys { it !in ciEnvironmentVariables } + mapOf(
                    "TUIST_URL" to server.url("/").toString().trimEnd('/'),
                    "TUIST_TOKEN" to "test-token",
                    "TUIST_SHARD_REFERENCE" to "shard-reference"
                )
            )

    private fun writeProject() {
        File(projectDir, "settings.gradle.kts").writeText(
            """
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
            }

            rootProject.name = "sharding-fixture"
            include(":app", ":lib", ":docs")
            """.trimIndent()
        )
        File(projectDir, "build.gradle.kts").writeText("")

        val app = File(projectDir, "app").apply { mkdirs() }
        File(app, "build.gradle.kts").writeText(
            """
            plugins {
                java
            }

            val otherTest by sourceSets.creating

            tasks.register<Test>("otherTest") {
                testClassesDirs = otherTest.output.classesDirs
                classpath = otherTest.runtimeClasspath
            }
            """.trimIndent()
        )
        writeTestClass(app, "test", "FooTest")
        writeTestClass(app, "otherTest", "OtherTest")

        val lib = File(projectDir, "lib").apply { mkdirs() }
        File(lib, "build.gradle.kts").writeText("plugins {\n    java\n}\n")
        writeTestClass(lib, "test", "LibTest")

        val docs = File(projectDir, "docs").apply { mkdirs() }
        File(docs, "build.gradle.kts").writeText("""println("Configured :docs")""")
    }

    private fun writeTestClass(projectDir: File, sourceSet: String, name: String) {
        val source = File(projectDir, "src/$sourceSet/java/com/example/$name.java")
        source.parentFile.mkdirs()
        source.writeText("package com.example;\n\npublic class $name {}\n")
    }

    private val ciEnvironmentVariables = setOf(
        "CI",
        "GITHUB_ACTIONS",
        "GITHUB_RUN_ID",
        "GITLAB_CI",
        "CI_PIPELINE_ID",
        "CIRCLECI",
        "CIRCLE_WORKFLOW_ID",
        "BUILDKITE",
        "BUILDKITE_BUILD_ID",
        "CM_BUILD_ID",
        "BITRISE_IO"
    )
}
