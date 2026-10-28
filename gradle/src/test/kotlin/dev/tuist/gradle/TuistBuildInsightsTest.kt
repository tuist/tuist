package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import org.gradle.testkit.runner.GradleRunner
import org.gradle.tooling.GradleConnector
import org.gradle.tooling.model.GradleProject
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.CsvSource
import org.junit.jupiter.params.provider.ValueSource
import java.io.File
import java.net.URI
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class TestGitInfoProvider(
    private val branch: String? = null,
    private val commitSha: String? = null,
    private val ref: String? = null,
    private val remoteUrlOrigin: String? = null
) : GitInfoProvider {
    override fun branch(): String? = branch
    override fun commitSha(): String? = commitSha
    override fun ref(): String? = ref
    override fun remoteUrlOrigin(): String? = remoteUrlOrigin
}

private class TestCIDetector(private val isCi: Boolean = false) : CIDetector {
    override fun isCi(): Boolean = isCi
}

class TuistBuildInsightsTest {

    private val gson = Gson()

    @Test
    fun `recording origin includes early samples and never clips earlier operations`() {
        val sample = MachineMetricSample(2.0, 10f, 100, 200, 0, 0, 0, 0)
        assertEquals(2000L, recordingStartedAt(listOf("1970-01-01T00:00:03Z"), listOf(sample), 4000))
        assertEquals(1000L, recordingStartedAt(listOf("1970-01-01T00:00:01Z"), listOf(sample), 4000))
        assertEquals(4000L, recordingStartedAt(emptyList(), emptyList(), 4000))
    }

    @Test
    fun `downsampling keeps the first and last machine samples`() {
        val downsampled = downsample((0 until 3602).toList(), maxCount = 3600)

        assertEquals(3600, downsampled.size)
        assertEquals(0, downsampled.first())
        assertEquals(3601, downsampled.last())
    }

    @Test
    fun `URL construction is correct`() {
        val baseUrl = "https://tuist.dev"
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$baseUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")

        assertEquals("https", url.scheme)
        assertEquals("tuist.dev", url.host)
        assertEquals("/api/projects/my-org/my-project/gradle/builds", url.path)
    }

    @Test
    fun `URL construction with trailing slash on server URL`() {
        val baseUrl = "https://tuist.dev/".trimEnd('/')
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$baseUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")

        assertEquals("/api/projects/my-org/my-project/gradle/builds", url.path)
    }

    @Test
    fun `TaskReportEntry serializes with snake_case field names`() {
        val entry = TaskReportEntry(
            taskPath = ":app:compileKotlin",
            outcome = TaskOutcome.LOCAL_HIT,
            cacheable = true,
            durationMs = 1500,
            cacheKey = "def456",
            cacheArtifactSize = 2048,
            startedAt = "2026-02-06T10:00:00Z",
            remoteCacheMiss = true,
            remoteCacheStored = true
        )

        val json = gson.toJson(entry)
        assertTrue(json.contains("\"task_path\""))
        assertTrue(json.contains("\"duration_ms\""))
        assertTrue(json.contains("\"cache_key\""))
        assertTrue(json.contains("\"cache_artifact_size\""))
        assertTrue(json.contains("\"started_at\""))
        assertTrue(json.contains("\"remote_cache_miss\""))
        assertTrue(json.contains("\"remote_cache_stored\""))
        assertTrue(!json.contains("\"taskPath\""))
        assertTrue(!json.contains("\"startedAt\""))
        assertTrue(!json.contains("\"cacheKey\""))
        assertTrue(!json.contains("\"cacheArtifactSize\""))
    }

    @Test
    fun `BuildReportRequest serializes with snake_case field names`() {
        val report = BuildReportRequest(
            id = "test-build-id",
            durationMs = 5000,
            status = "success",
            gradleVersion = "8.5",
            javaVersion = "17",
            isCi = true,
            gitBranch = "main",
            gitCommitSha = "abc",
            gitRef = "v1",
            gitRemoteUrlOrigin = "https://github.com/tuist/tuist.git",
            rootProjectName = null,
            requestedTasks = listOf("assembleRelease", "connectedAndroidTest"),
            tasks = emptyList(),
            customMetadata = BuildCustomMetadata(
                tags = listOf("nightly"),
                values = mapOf("team" to "android")
            ),
            startedAt = "2026-09-09T10:00:00.123Z",
            configurationCache = ConfigurationCacheReport(status = "reused")
        )

        val json = gson.toJson(report)
        assertTrue(json.contains("\"started_at\":\"2026-09-09T10:00:00.123Z\""))
        assertTrue(json.contains("\"duration_ms\""))
        assertTrue(json.contains("\"gradle_version\""))
        assertTrue(json.contains("\"java_version\""))
        assertTrue(json.contains("\"is_ci\""))
        assertTrue(json.contains("\"git_branch\""))
        assertTrue(json.contains("\"git_commit_sha\""))
        assertTrue(json.contains("\"git_ref\""))
        assertTrue(json.contains("\"git_remote_url_origin\""))
        assertTrue(json.contains("\"requested_tasks\""))
        assertTrue(json.contains("\"configuration_cache\""))
        assertTrue(json.contains("\"configuration_operations\""))
        assertTrue(json.contains("\"artifact_transforms\""))
        assertTrue(json.contains("\"assembleRelease\""))
        assertTrue(json.contains("\"connectedAndroidTest\""))
        assertTrue(json.contains("\"custom_metadata\""))
        assertTrue(json.contains("\"nightly\""))
        assertTrue(json.contains("\"team\""))
    }

    @Test
    fun `buildReport maps task outcomes to report entries`() {
        val tasks = listOf(
            TaskOutcomeData(
                taskPath = ":app:compileKotlin",
                outcome = TaskOutcome.EXECUTED,
                cacheable = true,
                durationMs = 3000,
                cacheKey = "abc123",
                cacheArtifactSize = 1024,
                startedAt = "2026-02-06T10:00:00Z"
            ),
            TaskOutcomeData(
                taskPath = ":app:test",
                outcome = TaskOutcome.UP_TO_DATE,
                cacheable = false,
                durationMs = 500,
                cacheKey = null,
                cacheArtifactSize = null,
                startedAt = "2026-02-06T10:00:03Z"
            )
        )

        val report = buildReport(
            id = "test-id",
            taskOutcomes = tasks,
            buildFailed = false,
            totalDurationMs = 5000,
            requestedTasks = listOf("assembleDebug"),
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals(listOf("assembleDebug"), report.requestedTasks)
        assertEquals(2, report.tasks.size)

        val first = report.tasks[0]
        assertEquals(":app:compileKotlin", first.taskPath)
        assertEquals(TaskOutcome.EXECUTED, first.outcome)
        assertTrue(first.cacheable)
        assertEquals(3000, first.durationMs)
        assertEquals("abc123", first.cacheKey)
        assertEquals(1024, first.cacheArtifactSize)
        assertEquals("2026-02-06T10:00:00Z", first.startedAt)

        val second = report.tasks[1]
        assertEquals(":app:test", second.taskPath)
        assertEquals(TaskOutcome.UP_TO_DATE, second.outcome)
        assertFalse(second.cacheable)
        assertEquals(500, second.durationMs)
        assertNull(second.cacheKey)
        assertNull(second.cacheArtifactSize)
    }

    @Test
    fun `buildReport includes cache and setup diagnostics`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = listOf(
                TaskOutcomeData(
                    taskPath = ":app:compileKotlin",
                    outcome = TaskOutcome.EXECUTED,
                    cacheable = true,
                    durationMs = 3000,
                    cacheKey = "abc123",
                    cacheArtifactSize = 1024,
                    startedAt = "2026-02-06T10:00:00Z",
                    remoteCacheMiss = true,
                    remoteCacheStored = true
                )
            ),
            buildFailed = false,
            totalDurationMs = 5000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider(),
            configurationCache = ConfigurationCacheReport(
                status = "invalid",
                invalidationReasons = listOf("environment variable changed")
            ),
            configurationOperations = listOf(
                ConfigurationOperationReportEntry(
                    phase = "project",
                    buildPath = ":",
                    projectPath = ":app",
                    durationMs = 1200,
                    startedAt = "2026-02-06T10:00:00Z"
                )
            ),
            artifactTransforms = listOf(
                ArtifactTransformReportEntry(
                    transformerName = "JetifyTransform",
                    transformActionClass = "com.android.build.gradle.internal.dependency.JetifyTransform",
                    subjectName = "example.jar",
                    artifactName = "example.jar",
                    consumerProjectPath = ":app",
                    durationMs = 300,
                    startedAt = "2026-02-06T10:00:01Z"
                )
            )
        )

        assertTrue(report.tasks.single().remoteCacheMiss)
        assertTrue(report.tasks.single().remoteCacheStored!!)
        assertEquals("invalid", report.configurationCache?.status)
        assertEquals(listOf("environment variable changed"), report.configurationCache?.invalidationReasons)
        assertEquals(":app", report.configurationOperations.single().projectPath)
        assertEquals("JetifyTransform", report.artifactTransforms.single().transformerName)
    }

    @Test
    fun `buildReport sets status to failure when buildFailed is true`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = listOf(
                TaskOutcomeData(":app:compile", TaskOutcome.EXECUTED, true, 1000, null, null, null)
            ),
            buildFailed = true,
            totalDurationMs = 1000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals("failure", report.status)
    }

    @Test
    fun `buildReport sets status to failure when any task failed`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = listOf(
                TaskOutcomeData(":app:compile", TaskOutcome.EXECUTED, true, 1000, null, null, null),
                TaskOutcomeData(":app:test", TaskOutcome.FAILED, false, 2000, null, null, null)
            ),
            buildFailed = false,
            totalDurationMs = 3000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals("failure", report.status)
    }

    @Test
    fun `buildReport sets status to success when all tasks succeed`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = listOf(
                TaskOutcomeData(":app:compile", TaskOutcome.EXECUTED, true, 1000, null, null, null),
                TaskOutcomeData(":lib:compile", TaskOutcome.LOCAL_HIT, true, 200, "key1", 512, null)
            ),
            buildFailed = false,
            totalDurationMs = 2000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals("success", report.status)
    }

    @Test
    fun `buildReport includes git info from provider`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider(
                branch = "feature/test",
                commitSha = "abc123def456",
                ref = "v1.0.0"
            )
        )

        assertEquals("feature/test", report.gitBranch)
        assertEquals("abc123def456", report.gitCommitSha)
        assertEquals("v1.0.0", report.gitRef)
        assertNull(report.gitRemoteUrlOrigin)
    }

    @Test
    fun `buildReport includes git remote URL origin from provider`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider(
                branch = "main",
                remoteUrlOrigin = "https://github.com/tuist/tuist.git"
            )
        )

        assertEquals("https://github.com/tuist/tuist.git", report.gitRemoteUrlOrigin)
    }

    @Test
    fun `buildReport includes CI detection`() {
        val ciReport = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            ciDetector = TestCIDetector(true),
            gitInfoProvider = TestGitInfoProvider()
        )
        assertTrue(ciReport.isCi)

        val localReport = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )
        assertFalse(localReport.isCi)
    }

    @Test
    fun `buildReport includes gradle version and root project name`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            gradleVersion = "8.5",
            rootProjectName = "my-app",
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals("8.5", report.gradleVersion)
        assertEquals("my-app", report.rootProjectName)
    }

    @Test
    fun `buildReport sets duration from parameter`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 42000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals(42000, report.durationMs)
    }

    @Test
    fun `buildReport includes custom metadata`() {
        val report = buildReport(
            id = "test-id",
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            customMetadata = BuildCustomMetadata(
                tags = listOf("nightly"),
                values = mapOf("team" to "android")
            ),
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals(listOf("nightly"), report.customMetadata.tags)
        assertEquals(mapOf("team" to "android"), report.customMetadata.values)
    }

    @ParameterizedTest
    @CsvSource("8.12.1,false", "8.12.1,true", "9.2.1,false", "9.2.1,true", "9.8.2,false", "9.8.2,true")
    fun `task cache metadata survives isolated configuration cache reuse`(gradleVersion: String, remote: Boolean, @TempDir projectDir: File) {
        val reports = ConcurrentLinkedQueue<BuildReportRequest>()
        val artifacts = ConcurrentHashMap<String, ByteArray>()
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse = when {
                request.path!!.endsWith("/gradle/builds") -> {
                    reports.add(gson.fromJson(request.body.readUtf8(), BuildReportRequest::class.java))
                    MockResponse().setResponseCode(201).setBody("""{"id": "build"}""")
                }
                request.method == "PUT" -> {
                    artifacts[request.path!!] = request.body.readByteArray()
                    MockResponse()
                }
                request.method == "GET" -> {
                    artifacts[request.path!!]?.let { MockResponse().setBody(Buffer().write(it)) }
                        ?: MockResponse().setResponseCode(404)
                }
                else -> MockResponse().setResponseCode(404)
            }
        }
        server.start()
        File(projectDir, "settings.gradle.kts").writeText("""
            plugins { id("dev.tuist") }
            tuist {
                project = "test-account/test-project"
                url = "${server.url("/")}"
                uploadInBackground = false
                network { proxy = false }
                buildCache {
                    enabled = $remote
                    allowInsecureProtocol = true
                }
            }
            buildCache {
                local {
                    isEnabled = ${!remote}
                    directory = File(settingsDir, "local-cache")
                }
            }
            rootProject.name = "cache-test"
            include(":app", ":lib")
        """.trimIndent())
        File(projectDir, "build.gradle.kts").writeText("""
            tasks.register("fails") { doLast { throw GradleException("expected failure") } }
        """.trimIndent())
        for (module in listOf("app", "lib")) {
            val directory = File(projectDir, module).apply { mkdirs() }
            File(directory, "build.gradle.kts").writeText("""
                @CacheableTask
                abstract class Generate : DefaultTask() {
                    @get:Input abstract val content: Property<String>
                    @get:OutputFile abstract val outputFile: RegularFileProperty
                    @TaskAction fun generate() { outputFile.get().asFile.writeText(content.get()) }
                }
                tasks.register<Generate>("generate") {
                    content.set("$module-output")
                    outputFile.set(layout.buildDirectory.file("output.txt"))
                }
            """.trimIndent())
        }
        val options = listOf("--build-cache", "--configuration-cache", "-Dorg.gradle.unsafe.isolated-projects=true", "--max-workers=2")
        val runner = GradleRunner.create()
            .withProjectDir(projectDir)
            .withGradleVersion(gradleVersion)
            .withArguments(listOf("generate") + options)
            .withEnvironment(System.getenv() + mapOf(
                "TUIST_TOKEN" to "test-token",
                "TUIST_URL" to server.url("/").toString(),
                "TUIST_CACHE_ENDPOINT" to server.url("/").toString()
            ))
            .withPluginClasspath()
        try {
            runner.build()
            assertEquals(1, reports.size)
            val initial = reports.last()
            for (module in listOf("app", "lib")) {
                val task = initial.tasks.single { it.taskPath == ":$module:generate" }
                assertEquals(TaskOutcome.EXECUTED, task.outcome)
                assertTrue(task.cacheable)
                assertTrue(!task.cacheKey.isNullOrBlank())
                assertTrue(task.cacheArtifactSize!! > 0)
                File(projectDir, "$module/build").deleteRecursively()
            }

            val cached = runner.build()
            assertTrue(cached.output.contains("Configuration cache entry reused"), cached.output)
            assertEquals(2, reports.size)
            for (module in listOf("app", "lib")) {
                val task = reports.last().tasks.single { it.taskPath == ":$module:generate" }
                val original = initial.tasks.single { it.taskPath == task.taskPath }
                assertEquals(if (remote) TaskOutcome.REMOTE_HIT else TaskOutcome.LOCAL_HIT, task.outcome)
                assertTrue(task.cacheable)
                assertEquals(original.cacheKey, task.cacheKey)
                assertEquals(original.cacheArtifactSize, task.cacheArtifactSize)
                assertEquals("$module-output", File(projectDir, "$module/build/output.txt").readText())
            }
            assertEquals(2, reports.last().tasks.map { it.cacheKey }.toSet().size)

            runner.build()
            assertEquals(3, reports.size)
            assertTrue(reports.last().tasks.all { it.outcome == TaskOutcome.UP_TO_DATE && it.cacheable })

            runner.withArguments(listOf("fails") + options).buildAndFail()
            assertEquals(4, reports.size)
            assertEquals("failure", reports.last().status)
            assertEquals(TaskOutcome.FAILED, reports.last().tasks.single().outcome)
        } finally {
            server.shutdown()
        }
    }

    @ParameterizedTest
    @ValueSource(strings = ["8.12.1", "9.2.1", "9.8.2"])
    fun `IDE model loading does not create empty build reports`(gradleVersion: String, @TempDir projectDir: File) {
        val reports = ConcurrentLinkedQueue<BuildReportRequest>()
        val server = MockWebServer()
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                reports.add(gson.fromJson(request.body.readUtf8(), BuildReportRequest::class.java))
                return MockResponse().setResponseCode(201).setBody("""{"id": "build"}""")
            }
        }
        server.start()
        val pluginClasspath = GradleRunner.create().withPluginClasspath().pluginClasspath
            .joinToString(", ") { "\"${it.absolutePath.replace("\\", "\\\\")}\"" }
        File(projectDir, "settings.gradle.kts").writeText("""
            buildscript { dependencies { classpath(files($pluginClasspath)) } }
            apply<dev.tuist.gradle.TuistPlugin>()
            extensions.configure<dev.tuist.gradle.TuistExtension>("tuist") {
                project = "test-account/test-project"
                url = "${server.url("/")}"
                uploadInBackground = false
                network { proxy = false }
                buildCache { enabled = false }
            }
            rootProject.name = "model-project"
        """.trimIndent())
        File(projectDir, "build.gradle.kts").writeText("plugins { java }")
        try {
            GradleConnector.newConnector()
                .useGradleVersion(gradleVersion)
                .forProjectDirectory(projectDir)
                .connect().use { connection ->
                    repeat(2) {
                        val model = connection.model(GradleProject::class.java)
                            .withArguments("-Dorg.gradle.unsafe.isolated-projects=true", "--max-workers=2")
                            .setEnvironmentVariables(System.getenv() + mapOf(
                                "TUIST_TOKEN" to "test-token",
                                "TUIST_URL" to server.url("/").toString(),
                                "TUIST_CACHE_ENDPOINT" to server.url("/").toString()
                            ))
                            .get()
                        assertEquals("model-project", model.name)
                        assertTrue(reports.isEmpty(), "IDE model loading must not upload a zero-task build")
                    }
                }
        } finally {
            server.shutdown()
        }
    }
}
