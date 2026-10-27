package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.CreateShardPlanParams1
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import java.io.File
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TuistPluginTest {

    @TempDir
    lateinit var testProjectDir: File

    private lateinit var settingsFile: File
    private lateinit var buildFile: File

    @BeforeEach
    fun setup() {
        settingsFile = File(testProjectDir, "settings.gradle.kts")
        buildFile = File(testProjectDir, "build.gradle.kts")
    }

    @Test
    fun `plugin can be applied to settings`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello from test project!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello", "--info")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `plugin gracefully handles missing project`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            // No tuist configuration - should not fail, just warn

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `plugin works when project is blank and falls back to tuist toml`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = ""
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("(from tuist.toml)"))
    }

    @Test
    fun `build cache can be disabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = false
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello", "--info")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("Build cache is disabled"))
    }

    @Test
    fun `plugin extension allows deprecated executable path without failing`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                @Suppress("DEPRECATION")
                executablePath = "/usr/local/bin/tuist"

                buildCache {
                    push = false
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `build cache push can be disabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = true
                    push = false
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `build cache allowInsecureProtocol can be enabled`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = true
                    allowInsecureProtocol = true
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `custom server URL can be configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                url = "https://custom.server.dev"
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
    }

    @Test
    fun `build insight metadata can be configured`() {
        settingsFile.writeText("""
            import dev.tuist.gradle.TuistGradleConfig

            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildInsights {
                    tag("nightly")
                    value("team", "android")
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            import dev.tuist.gradle.TuistGradleConfig

            tasks.register("printBuildMetadata") {
                doLast {
                    val config = project.extensions.extraProperties["tuist.config"] as TuistGradleConfig
                    println("tags=${'$'}{config.customMetadata.tags}")
                    println("team=${'$'}{config.customMetadata.values["team"]}")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("printBuildMetadata")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":printBuildMetadata")?.outcome)
        assertTrue(result.output.contains("tags=[nightly]"))
        assertTrue(result.output.contains("team=android"))
    }

    @Test
    fun `plugin reads network proxy from tuist toml`() {
        File(testProjectDir, "tuist.toml").writeText("""
            project = "test-account/test-project"

            [network]
            proxy = false
        """.trimIndent())

        settingsFile.writeText("""
            import dev.tuist.gradle.TuistGradleConfig

            plugins {
                id("dev.tuist")
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            import dev.tuist.gradle.TuistGradleConfig

            tasks.register("printProxyConfig") {
                doLast {
                    val config = project.extensions.extraProperties["tuist.config"] as TuistGradleConfig
                    println("proxy=${'$'}{config.network.proxy}")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("printProxyConfig")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":printProxyConfig")?.outcome)
        assertTrue(result.output.contains("proxy=false"))
    }

    @Test
    fun `plugin resolves the server URL from tuist toml before publishing shared configuration`() {
        File(testProjectDir, "tuist.toml").writeText("""
            project = "test-account/test-project"
            url = "http://localhost:8080"
        """.trimIndent())

        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            import dev.tuist.gradle.TuistGradleConfig

            tasks.register("printServerUrl") {
                doLast {
                    val config = project.extensions.extraProperties["tuist.config"] as TuistGradleConfig
                    println("url=${'$'}{config.url}")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("printServerUrl")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":printServerUrl")?.outcome)
        assertTrue(result.output.contains("url=http://localhost:8080"))
    }

    @Test
    fun `build insights logs message when configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "my-org/my-project"

                buildCache {
                    enabled = false
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("Build insights configured for my-org/my-project"))
    }

    @ParameterizedTest
    @CsvSource("8.12.1,true,true,GITLAB_CI", "8.12.1,true,true,CIRCLECI", "9.2.1,false,false,", "9.2.1,true,true,BUILDKITE", "9.8.2,true,true,")
    fun `multi-project integration survives configuration cache reuse`(
        gradleVersion: String,
        isolatedProjects: Boolean,
        sharding: Boolean,
        ciProvider: String?
    ) {
        val builds = ConcurrentLinkedQueue<BuildReportRequest>()
        val reports = ConcurrentLinkedQueue<TestReport>()
        val plans = ConcurrentLinkedQueue<CreateShardPlanParams1>()
        val shardRequests = AtomicInteger()
        val assignedLibSuite = AtomicReference("LibTest")
        val planId = "00000000-0000-0000-0000-000000000001"
        val gson = Gson()
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path!!.contains("test-cases?") -> MockResponse().setBody("""
                    {"test_cases": [
                        {"name": "muted()", "module": {"id": "app", "name": ":app"},
                         "suite": {"id": "app", "name": "AppTest"}, "state": "muted"},
                        {"name": "skipped", "module": {"id": "app", "name": ":app"},
                         "suite": {"id": "app", "name": "AppTest"}, "state": "skipped"}
                    ]}
                """.trimIndent())
                request.path!!.endsWith("/gradle/builds") -> {
                    builds.add(gson.fromJson(request.body.readUtf8(), BuildReportRequest::class.java))
                    MockResponse().setResponseCode(201).setBody("""{"id": "build"}""")
                }
                request.path!!.endsWith("/tests") -> {
                    reports.add(gson.fromJson(request.body.readUtf8(), TestReport::class.java))
                    MockResponse().setBody("""{"id": "tests"}""")
                }
                request.path!!.endsWith("/tests/shards") -> {
                    plans.add(gson.fromJson(request.body.readUtf8(), CreateShardPlanParams1::class.java))
                    MockResponse().setBody("""
                        {"id": "$planId", "reference": "plan", "shard_count": 1,
                         "shards": [{"index": 0, "test_targets": ["AppTest", "LibTest"], "estimated_duration_ms": 1000}]}
                    """.trimIndent())
                }
                request.path!!.endsWith("/tests/shards/plan/0") -> {
                    shardRequests.incrementAndGet()
                    val libSuite = assignedLibSuite.get()
                    MockResponse().setBody("""
                        {"shard_plan_id": "$planId", "modules": [":app", ":lib"],
                         "suites": {":app": ["AppTest"], ":lib": ["$libSuite"]}, "download_url": ""}
                    """.trimIndent())
                }
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()

        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"
                url = "${server.url("/")}"
                uploadInBackground = false
                network { proxy = false }
                testQuarantine {
                    enabled = true
                }
                buildCache {
                    enabled = false
                }
            }

            rootProject.name = "test-project"
            include(":app", ":lib")
        """.trimIndent())
        buildFile.writeText("")

        for (module in listOf("app", "lib")) {
            val directory = File(testProjectDir, module).apply { mkdirs() }
            File(directory, "build.gradle.kts").writeText("""
                plugins { java }
                repositories { mavenCentral() }
                dependencies {
                    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
                    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
                }
                tasks.test { useJUnitPlatform() }
            """.trimIndent())
            val className = if (module == "app") "AppTest" else "LibTest"
            File(directory, "src/test/java/$className.java").apply {
                parentFile.mkdirs()
                writeText("""
                    import org.junit.jupiter.api.Test;
                    public class $className {
                        @Test public void passes() {}
                        ${if (module == "app") """
                            @Test public void muted() { throw new AssertionError("muted failure"); }
                            @Test public void skipped() { throw new AssertionError("must not run"); }
                        """.trimIndent() else ""}
                    }
                """.trimIndent())
            }
            if (sharding) {
                File(directory, "src/test/java/ExcludedTest.java").writeText("""
                    import org.junit.jupiter.api.Test;
                    public class ExcludedTest {
                        @Test public void fails() { throw new AssertionError("not assigned to this shard"); }
                    }
                """.trimIndent())
                if (module == "lib") {
                    File(directory, "src/test/java/LibAlternateTest.java").writeText("""
                        import org.junit.jupiter.api.Test;
                        public class LibAlternateTest { @Test public void alternate() {} }
                    """.trimIndent())
                }
            }
        }

        val options = listOf(
            "--configuration-cache", "--max-workers=2", "--rerun-tasks",
            "-Dorg.gradle.unsafe.isolated-projects=$isolatedProjects"
        )
        val runner = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withGradleVersion(gradleVersion)
            .withEnvironment(System.getenv() - listOf(
                "GITHUB_ACTIONS", "GITLAB_CI", "CIRCLECI", "BUILDKITE", "CM_BUILD_ID", "BITRISE_IO"
            ) + mapOf(
                "TUIST_TOKEN" to "test-token",
                "TUIST_URL" to server.url("/").toString(),
                "TUIST_CACHE_ENDPOINT" to server.url("/").toString(),
                "TUIST_SHARD_REFERENCE" to "plan",
                "TUIST_SHARD_INDEX" to if (sharding) "0" else ""
            ) + if (ciProvider == null) emptyMap() else mapOf(ciProvider to "true"))
            .withPluginClasspath()

        try {
            if (sharding) {
                runner.withEnvironment(runner.environment!! + ("TUIST_SHARD_INDEX" to ""))
                for (run in 1..2) {
                    val result = runner.withArguments(listOf("tuistPrepareTestShards") + options).build()
                    assertEquals(TaskOutcome.SUCCESS, result.task(":tuistPrepareTestShards")?.outcome)
                    assertEquals(null, result.task(":app:test"))
                    assertEquals(null, result.task(":lib:test"))
                    assertEquals(run, plans.size)
                    assertEquals(listOf(":app", ":lib"), plans.last().modules)
                    assertEquals(null, plans.last().testSuites)
                    assertEquals(null, result.task(":app:compileTestJava"))
                    assertEquals(null, result.task(":lib:compileTestJava"))
                    assertEquals(builds.last().id, plans.last().gradleBuildId.toString())
                    assertTrue(result.output.contains(
                        if (run == 1) "Configuration cache entry stored" else "Configuration cache entry reused"
                    ), result.output)
                }
                runner.withEnvironment(runner.environment!! + ("TUIST_SHARD_INDEX" to "0"))
                builds.clear()
            }
            val runCount = if (sharding) 3 else 2
            for (run in 1..runCount) {
                if (run == 2) assignedLibSuite.set("LibAlternateTest")
                val previousShardRequests = shardRequests.get()
                val result = runner.withArguments(listOf("test") + options).build()
                assertEquals(TaskOutcome.SUCCESS, result.task(":app:test")?.outcome, result.output)
                assertEquals(TaskOutcome.SUCCESS, result.task(":lib:test")?.outcome, result.output)
                assertTrue(result.output.contains(
                    if (run == 1 || sharding && run == 2) "Configuration cache entry stored" else "Configuration cache entry reused"
                ), result.output)

                assertEquals(run, builds.size)
                assertEquals(run, reports.size)
                val build = builds.last()
                val report = reports.last()
                assertEquals(build.id, report.gradleBuildId)
                assertEquals(listOf("test"), build.requestedTasks)
                assertEquals("success", report.status)
                assertEquals(setOf(":app", ":lib"), report.testModules.map { it.name }.toSet())
                val appTests = report.testModules.single { it.name == ":app" }.testCases
                assertEquals(setOf("passes()", "muted()"), appTests.map { it.name }.toSet())
                assertTrue(appTests.single { it.name == "muted()" }.isQuarantined)
                val libTest = report.testModules.single { it.name == ":lib" }.testCases.single()
                assertEquals(if (sharding && run >= 2) "alternate()" else "passes()", libTest.name)
                if (sharding) {
                    assertEquals(planId, report.shardPlanId)
                    assertEquals(0, report.shardIndex)
                    assertTrue(shardRequests.get() > previousShardRequests, "Assignments must be checked again on cache reuse")
                }
            }
            assertEquals(runCount, builds.map { it.id }.toSet().size)
        } finally {
            server.shutdown()
        }
    }

    @Test
    fun `plugin stores a Gradle configuration cache entry`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "test-account/test-project"

                buildCache {
                    enabled = false
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello")
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello", "--configuration-cache")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.UP_TO_DATE, result.task(":hello")?.outcome)
        assertTrue(
            result.output.contains("Configuration cache entry stored"),
            "Gradle did not store a configuration cache entry:\n${result.output}"
        )

    }

    @Test
    fun `plugin logs message when build cache is configured`() {
        settingsFile.writeText("""
            plugins {
                id("dev.tuist")
            }

            tuist {
                project = "my-org/my-project"

                buildCache {
                    enabled = true
                }
            }

            rootProject.name = "test-project"
        """.trimIndent())

        buildFile.writeText("""
            tasks.register("hello") {
                doLast {
                    println("Hello!")
                }
            }
        """.trimIndent())

        val result = GradleRunner.create()
            .withProjectDir(testProjectDir)
            .withArguments("hello")
            .withPluginClasspath()
            .build()

        assertEquals(TaskOutcome.SUCCESS, result.task(":hello")?.outcome)
        assertTrue(result.output.contains("Remote build cache configured for my-org/my-project"))
    }
}
