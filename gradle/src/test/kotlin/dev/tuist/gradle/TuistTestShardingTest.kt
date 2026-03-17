package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.ShardAssignment
import dev.tuist.gradle.api.model.ShardAssignmentResponse
import dev.tuist.gradle.api.model.ShardPlanResponse
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistTestShardingTest {

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
        val httpClient = TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean) = CacheConfiguration(
                    url = baseUrl,
                    token = "test-token",
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )
        return TuistTestShardingService(httpClient = httpClient, baseUrl = baseUrl)
    }

    @Test
    fun `createShardPlan sends correct request and parses response`() {
        val service = createService()

        val responseBody = Gson().toJson(
            ShardPlanResponse(
                sessionId = "github-123-1",
                shardCount = 3,
                shards = listOf(
                    ShardAssignment(index = 0, testTargets = listOf("com.example.LoginTest", "com.example.LogoutTest"), estimatedDurationMs = 5000),
                    ShardAssignment(index = 1, testTargets = listOf("com.example.PaymentTest"), estimatedDurationMs = 4500),
                    ShardAssignment(index = 2, testTargets = listOf("com.example.ProfileTest", "com.example.SettingsTest"), estimatedDurationMs = 4800)
                ),
                uploadId = "upload-abc"
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.createShardPlan(
            sessionId = "github-123-1",
            testSuites = listOf("com.example.LoginTest", "com.example.LogoutTest", "com.example.PaymentTest", "com.example.ProfileTest", "com.example.SettingsTest"),
            shardMax = 3,
            shardMin = 1,
            shardMaxDuration = null
        )

        assertNotNull(result)
        assertEquals(3, result.shardCount)
        assertEquals(3, result.shards.size)
        assertEquals(listOf("com.example.LoginTest", "com.example.LogoutTest"), result.shards[0].testTargets)

        val request = mockWebServer.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.contains("/api/projects/test-account/test-project/tests/shards"))
    }

    @Test
    fun `createShardPlan returns null on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        val result = service.createShardPlan(
            sessionId = "github-456-1",
            testSuites = listOf("com.example.Test"),
            shardMax = 2,
            shardMin = null,
            shardMaxDuration = null
        )

        assertNull(result)
    }

    @Test
    fun `createShardPlan sends correct JSON body`() {
        val service = createService()

        val responseBody = Gson().toJson(
            ShardPlanResponse(
                sessionId = "test-session",
                shardCount = 2,
                shards = listOf(
                    ShardAssignment(index = 0, testTargets = listOf("com.example.Test1"), estimatedDurationMs = 3000),
                    ShardAssignment(index = 1, testTargets = listOf("com.example.Test2"), estimatedDurationMs = 3000)
                ),
                uploadId = "upload-xyz"
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        service.createShardPlan(
            sessionId = "test-session",
            testSuites = listOf("com.example.Test1", "com.example.Test2"),
            shardMax = 2,
            shardMin = 1,
            shardMaxDuration = 60
        )

        val request = mockWebServer.takeRequest()
        val body = request.body.readUtf8()
        assertTrue(body.contains("\"session_id\":\"test-session\""))
        assertTrue(body.contains("\"shard_max\":2"))
        assertTrue(body.contains("\"shard_min\":1"))
        assertTrue(body.contains("\"shard_max_duration\":60"))
        assertTrue(body.contains("\"granularity\":\"suite\""))
    }

    @Test
    fun `getShardAssignment parses response correctly`() {
        val service = createService()

        val responseBody = Gson().toJson(
            ShardAssignmentResponse(
                testTargets = listOf("com.example.LoginTest", "com.example.LogoutTest"),
                xctestrunDownloadUrl = null,
                bundleDownloadUrl = null
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getShardAssignment("github-123-1", 0)

        assertNotNull(result)
        assertEquals(2, result.testTargets.size)
        assertEquals("com.example.LoginTest", result.testTargets[0])

        val request = mockWebServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.contains("/api/projects/test-account/test-project/tests/shards/github-123-1/0"))
    }

    @Test
    fun `getShardAssignment returns null on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        val result = service.getShardAssignment("nonexistent-session", 0)

        assertNull(result)
    }

    @Test
    fun `getShardAssignment returns null on network error`() {
        val baseUrl = "http://localhost:1"
        val httpClient = TuistHttpClient(
            configurationProvider = object : ConfigurationProvider {
                override fun getConfiguration(forceRefresh: Boolean) = CacheConfiguration(
                    url = baseUrl,
                    token = "test-token",
                    accountHandle = "test-account",
                    projectHandle = "test-project"
                )
            },
            connectTimeoutMs = 100,
            readTimeoutMs = 100
        )
        val service = TuistTestShardingService(httpClient = httpClient, baseUrl = baseUrl)

        val result = service.getShardAssignment("session-123", 0)

        assertNull(result)
    }

    @Test
    fun `deriveSessionId returns null without CI environment`() {
        val service = createService()
        val sessionId = service.deriveSessionId()
        if (System.getenv("GITHUB_RUN_ID") == null &&
            System.getenv("CIRCLE_WORKFLOW_ID") == null &&
            System.getenv("BUILDKITE_BUILD_ID") == null &&
            System.getenv("CI_PIPELINE_ID") == null &&
            System.getenv("CM_BUILD_ID") == null
        ) {
            assertNull(sessionId)
        }
    }
}
