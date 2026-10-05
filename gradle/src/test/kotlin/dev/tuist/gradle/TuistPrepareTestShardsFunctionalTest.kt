package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.JsonParser
import dev.tuist.gradle.api.model.ShardPlan
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
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
    fun `compiles the test classes of every test task and plans shards for them`() {
        val result = runner("tuistPrepareTestShards").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileTestJava")?.outcome, result.output)
        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileOtherTestJava")?.outcome, result.output)
        assertEquals(TaskOutcome.SUCCESS, result.task(":tuistPrepareTestShards")?.outcome, result.output)
        assertEquals(listOf("com.example.FooTest", "com.example.OtherTest"), plannedTestSuites())
    }

    @Test
    fun `only compiles and plans the test task selected with tuistShardTestTask`() {
        val result = runner("tuistPrepareTestShards", "-PtuistShardTestTask=otherTest").build()

        assertEquals(null, result.task(":app:compileTestJava"), result.output)
        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileOtherTestJava")?.outcome, result.output)
        assertEquals(listOf("com.example.OtherTest"), plannedTestSuites())
    }

    @Test
    fun `configures subprojects when invoked by path with configuration on demand`() {
        enableConfigurationOnDemand()

        val result = runner(":tuistPrepareTestShards").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":tuistPrepareTestShards")?.outcome, result.output)
        assertTrue(result.output.contains("Configured :docs"), result.output)
        assertEquals(listOf("com.example.FooTest", "com.example.OtherTest"), plannedTestSuites())
    }

    @Test
    fun `finds the selected test task when invoked by path with configuration on demand`() {
        enableConfigurationOnDemand()

        val result = runner(":tuistPrepareTestShards", "-PtuistShardTestTask=otherTest").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileOtherTestJava")?.outcome, result.output)
        assertEquals(listOf("com.example.OtherTest"), plannedTestSuites())
    }

    @Test
    fun `leaves unrelated projects unconfigured with configuration on demand when sharding is not requested`() {
        enableConfigurationOnDemand()

        val result = runner(":app:compileTestJava").build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":app:compileTestJava")?.outcome, result.output)
        assertFalse(result.output.contains("Configured :docs"), result.output)
    }

    @Test
    fun `fails when no project has the selected test task`() {
        val result = runner("tuistPrepareTestShards", "-PtuistShardTestTask=missingTest").buildAndFail()

        assert(result.output.contains("No test task named 'missingTest'")) { result.output }
    }

    private fun enableConfigurationOnDemand() {
        File(projectDir, "gradle.properties").writeText("org.gradle.configureondemand=true\n")
    }

    private fun plannedTestSuites(): List<String> {
        val body = JsonParser.parseString(shardPlanRequests.single()).asJsonObject
        return body.getAsJsonArray("test_suites").map { it.asString }
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
            include(":app", ":docs")
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
