package dev.tuist.gradle

import com.google.gson.Gson
import dev.tuist.gradle.api.model.Shard
import dev.tuist.gradle.api.model.ShardPlan
import dev.tuist.gradle.api.model.ShardPlanShardsInner
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
        return TuistTestShardingService(
            baseUrl = baseUrl,
            token = "test-token",
            accountHandle = "test-account",
            projectHandle = "test-project"
        )
    }

    @Test
    fun `createShardPlan sends correct request and parses response`() {
        val service = createService()

        val responseBody = Gson().toJson(
            ShardPlan(
                planId = "github-123-1",
                shardCount = 3,
                shards = listOf(
                    ShardPlanShardsInner(index = 0, testTargets = listOf("com.example.LoginTest", "com.example.LogoutTest"), estimatedDurationMs = 5000),
                    ShardPlanShardsInner(index = 1, testTargets = listOf("com.example.PaymentTest"), estimatedDurationMs = 4500),
                    ShardPlanShardsInner(index = 2, testTargets = listOf("com.example.ProfileTest", "com.example.SettingsTest"), estimatedDurationMs = 4800)
                ),
                uploadId = "upload-abc"
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.createShardPlan(
            planId = "github-123-1",
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
            planId = "github-456-1",
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
            ShardPlan(
                planId = "test-plan",
                shardCount = 2,
                shards = listOf(
                    ShardPlanShardsInner(index = 0, testTargets = listOf("com.example.Test1"), estimatedDurationMs = 3000),
                    ShardPlanShardsInner(index = 1, testTargets = listOf("com.example.Test2"), estimatedDurationMs = 3000)
                ),
                uploadId = "upload-xyz"
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        service.createShardPlan(
            planId = "test-plan",
            testSuites = listOf("com.example.Test1", "com.example.Test2"),
            shardMax = 2,
            shardMin = 1,
            shardMaxDuration = 60
        )

        val request = mockWebServer.takeRequest()
        val body = request.body.readUtf8()
        assertTrue(body.contains("\"plan_id\":\"test-plan\""))
        assertTrue(body.contains("\"shard_max\":2"))
        assertTrue(body.contains("\"shard_min\":1"))
        assertTrue(body.contains("\"shard_max_duration\":60"))
        assertTrue(body.contains("\"granularity\":\"suite\""))
    }

    @Test
    fun `getShard parses response correctly`() {
        val service = createService()

        val responseBody = Gson().toJson(
            Shard(
                modules = listOf("AppModule"),
                suites = mapOf("AppModule" to listOf("com.example.LoginTest", "com.example.LogoutTest")),
                downloadUrl = "https://download.example.com/bundle.zip"
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getShard("github-123-1", 0)

        assertNotNull(result)
        assertEquals(listOf("AppModule"), result.modules)
        assertEquals(listOf("com.example.LoginTest", "com.example.LogoutTest"), result.suites["AppModule"])

        val request = mockWebServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.contains("/api/projects/test-account/test-project/tests/shards/github-123-1/0"))
    }

    @Test
    fun `getShard returns null on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        val result = service.getShard("nonexistent-plan", 0)

        assertNull(result)
    }

    @Test
    fun `getShard returns null on network error`() {
        val service = TuistTestShardingService(
            baseUrl = "http://localhost:1",
            token = "test-token",
            accountHandle = "test-account",
            projectHandle = "test-project"
        )

        val result = service.getShard("plan-123", 0)

        assertNull(result)
    }

    @Test
    fun `derivePlanId returns null without CI environment`() {
        val service = createService()
        val planId = service.derivePlanId()
        if (System.getenv("GITHUB_RUN_ID") == null &&
            System.getenv("CIRCLE_WORKFLOW_ID") == null &&
            System.getenv("BUILDKITE_BUILD_ID") == null &&
            System.getenv("CI_PIPELINE_ID") == null &&
            System.getenv("CM_BUILD_ID") == null
        ) {
            assertNull(planId)
        }
    }
}
