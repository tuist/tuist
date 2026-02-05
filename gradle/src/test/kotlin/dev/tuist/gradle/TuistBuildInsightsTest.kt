package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
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

        val client = DefaultBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 5000,
            status = "success",
            gradleVersion = "8.5",
            javaVersion = "17.0.1",
            isCi = false,
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v1.0.0",
            avoidanceSavingsMs = 2000,
            tasks = listOf(
                TaskReportEntry(
                    taskPath = ":app:compileKotlin",
                    outcome = "from_cache",
                    cacheable = true,
                    durationMs = 1000,
                    taskType = "org.jetbrains.kotlin.gradle.tasks.KotlinCompile"
                ),
                TaskReportEntry(
                    taskPath = ":app:test",
                    outcome = "executed",
                    cacheable = true,
                    durationMs = 3000,
                    taskType = null
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
        assertEquals("from_cache", tasks[0]["outcome"])
        assertEquals(true, tasks[0]["cacheable"])
    }

    @Test
    fun `HTTP client returns null on non-201 response`() {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(401)
                .setBody("""{"error": "unauthorized"}""")
        )

        val client = DefaultBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 1000,
            status = "success",
            gradleVersion = null,
            javaVersion = null,
            isCi = false,
            gitBranch = null,
            gitCommitSha = null,
            gitRef = null,
            avoidanceSavingsMs = 0,
            tasks = emptyList()
        )

        val url = URI(mockWebServer.url("/api/projects/org/proj/gradle/builds").toString())
        val response = client.postBuildReport(url, "bad-token", report)

        assertNull(response)
    }

    @Test
    fun `HTTP client returns null on 500 server error`() {
        mockWebServer.enqueue(
            MockResponse()
                .setResponseCode(500)
                .setBody("""{"error": "internal server error"}""")
        )

        val client = DefaultBuildInsightsHttpClient()
        val report = BuildReportRequest(
            durationMs = 1000,
            status = "success",
            gradleVersion = null,
            javaVersion = null,
            isCi = false,
            gitBranch = null,
            gitCommitSha = null,
            gitRef = null,
            avoidanceSavingsMs = 0,
            tasks = emptyList()
        )

        val url = URI(mockWebServer.url("/api/projects/org/proj/gradle/builds").toString())
        val response = client.postBuildReport(url, "token", report)

        assertNull(response)
    }

    @Test
    fun `URL construction is correct`() {
        val serverUrl = "https://tuist.dev"
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$serverUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")

        assertEquals("https", url.scheme)
        assertEquals("tuist.dev", url.host)
        assertEquals("/api/projects/my-org/my-project/gradle/builds", url.path)
    }

    @Test
    fun `URL construction with trailing slash on server URL`() {
        val serverUrl = "https://tuist.dev/".trimEnd('/')
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$serverUrl/api/projects/$accountHandle/$projectHandle/gradle/builds")

        assertEquals("/api/projects/my-org/my-project/gradle/builds", url.path)
    }

    @Test
    fun `TaskReportEntry serializes with snake_case field names`() {
        val entry = TaskReportEntry(
            taskPath = ":app:compileKotlin",
            outcome = "from_cache",
            cacheable = true,
            durationMs = 1500,
            taskType = "KotlinCompile"
        )

        val json = gson.toJson(entry)
        assertTrue(json.contains("\"task_path\""))
        assertTrue(json.contains("\"duration_ms\""))
        assertTrue(json.contains("\"task_type\""))
        assertTrue(!json.contains("\"taskPath\""))
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
            avoidanceSavingsMs = 2000,
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
        assertTrue(json.contains("\"avoidance_savings_ms\""))
    }
}
