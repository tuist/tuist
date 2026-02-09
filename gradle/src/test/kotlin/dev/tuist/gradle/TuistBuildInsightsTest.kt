package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

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
}
