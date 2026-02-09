package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistBuildInsightsTest {

    private lateinit var mockWebServer: MockWebServer
    private val gson = Gson()

    @BeforeEach
    fun setup() {
        mockWebServer = MockWebServer()
        mockWebServer.start()
    }

    @AfterEach
    fun tearDown() {
        mockWebServer.shutdown()
    }

    @Test
    fun `HTTP client sends correct JSON body and auth header`() {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(201)
                .setBody("""{"id": "test-build-id"}""")
                .addHeader("Content-Type", "application/json")
        )

        val client = UrlConnectionBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 5000,
            status = "success",
            gradleVersion = "8.5",
            javaVersion = "17.0.1",
            isCi = false,
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v1.0.0",
            rootProjectName = null,

            tasks = listOf(
                TaskReportEntry(
                    taskPath = ":app:compileKotlin",
                    outcome = TaskOutcome.LOCAL_HIT,
                    cacheable = true,
                    durationMs = 1000,
                    cacheKey = "abc123",
                    cacheArtifactSize = 1024,
                    startedAt = "2026-02-06T10:00:00Z"
                ),
                TaskReportEntry(
                    taskPath = ":app:test",
                    outcome = TaskOutcome.EXECUTED,
                    cacheable = true,
                    durationMs = 3000,
                    cacheKey = null,
                    cacheArtifactSize = null,
                    startedAt = "2026-02-06T10:00:01Z"
                )
            )
        )

        val url = URI(mockWebServer.url("/api/projects/my-org/my-project/gradle/builds").toString())
        val response = client.postBuildReport(url, "test-token", report)

        assertNotNull(response)
        assertEquals("test-build-id", response.id)

        val request = mockWebServer.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/api/projects/my-org/my-project/gradle/builds", request.path)
        assertEquals("Bearer test-token", request.getHeader("Authorization"))
        assertEquals("application/json", request.getHeader("Content-Type"))

        val body = gson.fromJson(request.body.readUtf8(), Map::class.java)
        assertEquals(5000.0, body["duration_ms"])
        assertEquals("success", body["status"])
        assertEquals("8.5", body["gradle_version"])
        assertEquals("17.0.1", body["java_version"])
        assertEquals(false, body["is_ci"])
        assertEquals("main", body["git_branch"])
        assertEquals("abc123", body["git_commit_sha"])
        assertEquals("v1.0.0", body["git_ref"])

        @Suppress("UNCHECKED_CAST")
        val tasks = body["tasks"] as List<Map<String, Any>>
        assertEquals(2, tasks.size)
        assertEquals(":app:compileKotlin", tasks[0]["task_path"])
        assertEquals("local_hit", tasks[0]["outcome"])
        assertEquals(true, tasks[0]["cacheable"])
    }

    @Test
    fun `HTTP client throws TokenExpiredException on 401 response`() {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(401)
                .setBody("""{"error": "unauthorized"}""")
        )

        val client = UrlConnectionBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 1000,
            status = "success",
            gradleVersion = null,
            javaVersion = null,
            isCi = false,
            gitBranch = null,
            gitCommitSha = null,
            gitRef = null,
            rootProjectName = null,

            tasks = emptyList()
        )

        val url = URI(mockWebServer.url("/api/projects/org/proj/gradle/builds").toString())
        assertFailsWith<TokenExpiredException> {
            client.postBuildReport(url, "bad-token", report)
        }
    }

    @Test
    fun `HTTP client returns null on 500 server error`() {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"error": "internal server error"}""")
        )

        val client = UrlConnectionBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 1000,
            status = "success",
            gradleVersion = null,
            javaVersion = null,
            isCi = false,
            gitBranch = null,
            gitCommitSha = null,
            gitRef = null,
            rootProjectName = null,

            tasks = emptyList()
        )

        val url = URI(mockWebServer.url("/api/projects/org/proj/gradle/builds").toString())
        val response = client.postBuildReport(url, "token", report)

        assertNull(response)
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
