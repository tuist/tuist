package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertEquals
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

    private fun createHttpClient(token: String = "test-token"): TuistHttpClient {
        val baseUrl = mockWebServer.url("/").toString().trimEnd('/')
        return TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean): TuistCacheConfiguration = TuistCacheConfiguration(
                    url = baseUrl,
                    token = token,
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
    }

    @Test
    fun `openConnection sets Bearer token header`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(200))

        val httpClient = createHttpClient(token = "my-secret-token")
        val url = URI(mockWebServer.url("/test").toString())

        httpClient.execute { config ->
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            connection.responseCode
        }

        val request = mockWebServer.takeRequest()
        assertEquals("Bearer my-secret-token", request.getHeader("Authorization"))
    }

    @Test
    fun `execute retries once on TokenExpiredException`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(401))
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("ok"))

        val httpClient = createHttpClient()

        val result = httpClient.execute { config ->
            val url = URI(mockWebServer.url("/test").toString())
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            when (connection.responseCode) {
                HttpURLConnection.HTTP_OK -> "success"
                HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                else -> "error"
            }
        }

        assertEquals("success", result)
        assertEquals(2, mockWebServer.requestCount)
    }

    @Test
    fun `execute returns result directly on success`() {
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody("hello"))

        val httpClient = createHttpClient()

        val result = httpClient.execute { config ->
            val url = URI(mockWebServer.url("/test").toString())
            val connection = httpClient.openConnection(url, config)
            connection.requestMethod = "GET"
            connection.responseCode
        }

        assertEquals(200, result)
        assertEquals(1, mockWebServer.requestCount)
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
