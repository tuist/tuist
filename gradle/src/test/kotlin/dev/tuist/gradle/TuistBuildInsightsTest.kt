package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class TestGitInfoProvider(
    private val branch: String? = null,
    private val commitSha: String? = null,
    private val ref: String? = null
) : GitInfoProvider {
    override fun branch(): String? = branch
    override fun commitSha(): String? = commitSha
    override fun ref(): String? = ref
}

private class TestCIDetector(private val isCi: Boolean = false) : CIDetector {
    override fun isCi(): Boolean = isCi
}

class TuistBuildInsightsTest {

    private val gson = Gson()

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
            startedAt = "2026-02-06T10:00:00Z"
        )

        val json = gson.toJson(entry)
        assertTrue(json.contains("\"task_path\""))
        assertTrue(json.contains("\"duration_ms\""))
        assertTrue(json.contains("\"cache_key\""))
        assertTrue(json.contains("\"cache_artifact_size\""))
        assertTrue(json.contains("\"started_at\""))
        assertTrue(!json.contains("\"taskPath\""))
        assertTrue(!json.contains("\"startedAt\""))
        assertTrue(!json.contains("\"cacheKey\""))
        assertTrue(!json.contains("\"cacheArtifactSize\""))
    }

    @Test
    fun `TaskCacheMetadata defaults are correct`() {
        val metadata = TaskCacheMetadata()
        assertNull(metadata.cacheKey)
        assertNull(metadata.artifactSize)
        assertEquals(CacheHitType.MISS, metadata.cacheHitType)
    }

    @Test
    fun `TaskCacheMetadata copy preserves and overrides fields`() {
        val metadata = TaskCacheMetadata(cacheKey = "abc123", artifactSize = 4096, cacheHitType = CacheHitType.REMOTE)
        assertEquals("abc123", metadata.cacheKey)
        assertEquals(4096L, metadata.artifactSize)
        assertEquals(CacheHitType.REMOTE, metadata.cacheHitType)

        val updated = metadata.copy(cacheHitType = CacheHitType.LOCAL, artifactSize = 8192)
        assertEquals("abc123", updated.cacheKey)
        assertEquals(8192L, updated.artifactSize)
        assertEquals(CacheHitType.LOCAL, updated.cacheHitType)
    }

    @Test
    fun `BuildReportRequest serializes with snake_case field names`() {
        val report = BuildReportRequest(
            durationMs = 5000,
            status = "success",
            gradleVersion = "8.5",
            javaVersion = "17",
            isCi = true,
            gitBranch = "main",
            gitCommitSha = "abc",
            gitRef = "v1",
            rootProjectName = null,
            tasks = emptyList()
        )

        val json = gson.toJson(report)
        assertTrue(json.contains("\"duration_ms\""))
        assertTrue(json.contains("\"gradle_version\""))
        assertTrue(json.contains("\"java_version\""))
        assertTrue(json.contains("\"is_ci\""))
        assertTrue(json.contains("\"git_branch\""))
        assertTrue(json.contains("\"git_commit_sha\""))
        assertTrue(json.contains("\"git_ref\""))
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
            taskOutcomes = tasks,
            buildFailed = false,
            totalDurationMs = 5000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

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
    fun `buildReport sets status to failure when buildFailed is true`() {
        val report = buildReport(
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
    }

    @Test
    fun `buildReport includes CI detection`() {
        val ciReport = buildReport(
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 100,
            ciDetector = TestCIDetector(true),
            gitInfoProvider = TestGitInfoProvider()
        )
        assertTrue(ciReport.isCi)

        val localReport = buildReport(
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
            taskOutcomes = emptyList(),
            buildFailed = false,
            totalDurationMs = 42000,
            ciDetector = TestCIDetector(false),
            gitInfoProvider = TestGitInfoProvider()
        )

        assertEquals(42000, report.durationMs)
    }
}
