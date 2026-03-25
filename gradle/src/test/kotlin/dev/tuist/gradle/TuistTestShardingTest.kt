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
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistTestShardingServiceTest {

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

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(Gson().toJson(
            ShardPlan(
                reference = "github-123-1",
                shardCount = 2,
                shards = listOf(
                    ShardPlanShardsInner(index = 0, testTargets = listOf("com.example.LoginTest"), estimatedDurationMs = 5000),
                    ShardPlanShardsInner(index = 1, testTargets = listOf("com.example.SignupTest"), estimatedDurationMs = 4500)
                ),
                id = java.util.UUID.randomUUID()
            )
        )))

        val result = service.createShardPlan(
            reference = "github-123-1",
            testSuites = listOf("com.example.LoginTest", "com.example.SignupTest"),
            shardMax = 2,
            shardMin = null,
            shardMaxDuration = null
        )

        assertEquals(2, result.shardCount)
        assertEquals("com.example.LoginTest", result.shards[0].testTargets[0])

        val request = mockWebServer.takeRequest()
        assertEquals("POST", request.method)
        assertTrue(request.path!!.endsWith("/api/projects/test-account/test-project/tests/shards"))
        assertTrue(request.getHeader("Authorization") == "Bearer test-token")
    }

    @Test
    fun `createShardPlan throws on server error`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        assertThrows<org.gradle.api.GradleException> {
            service.createShardPlan(
                reference = "plan-1",
                testSuites = listOf("com.example.Test"),
                shardMax = 2,
                shardMin = null,
                shardMaxDuration = null
            )
        }
    }

    @Test
    fun `getShard returns shard with modules and suites`() {
        val service = createService()

        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(Gson().toJson(
            Shard(
                modules = listOf("AppModule"),
                shardPlanId = java.util.UUID.randomUUID(),
                suites = mapOf("AppModule" to listOf("com.example.LoginTest", "com.example.LogoutTest")),
                downloadUrl = "https://download.example.com/bundle.zip"
            )
        )))

        val result = service.getShard("plan-1", 0)

        assertEquals(listOf("AppModule"), result.modules)
        assertEquals(listOf("com.example.LoginTest", "com.example.LogoutTest"), result.suites["AppModule"])
    }

    @Test
    fun `getShard throws on not found`() {
        val service = createService()
        mockWebServer.enqueue(MockResponse().setResponseCode(404).setBody("Not Found"))

        assertThrows<org.gradle.api.GradleException> {
            service.getShard("nonexistent", 0)
        }
    }
}

class DeriveReferenceTest {

    @Test
    fun `deriveReference returns null without CI environment`() {
        val service = TuistTestShardingService(
            baseUrl = "http://localhost",
            token = "token",
            accountHandle = "account",
            projectHandle = "project"
        )
        if (System.getenv("GITHUB_RUN_ID") == null &&
            System.getenv("CIRCLE_WORKFLOW_ID") == null &&
            System.getenv("BUILDKITE_BUILD_ID") == null &&
            System.getenv("CI_PIPELINE_ID") == null &&
            System.getenv("CM_BUILD_ID") == null
        ) {
            assertNull(service.deriveReference())
        }
    }
}

class DetectCIProviderTest {

    @Test
    fun `detectCIProvider returns null without CI environment`() {
        if (System.getenv("GITHUB_ACTIONS") == null &&
            System.getenv("GITLAB_CI") == null &&
            System.getenv("CIRCLECI") == null &&
            System.getenv("BUILDKITE") == null &&
            System.getenv("CM_BUILD_ID") == null &&
            System.getenv("BITRISE_IO") == null
        ) {
            assertNull(detectCIProvider())
        }
    }

    @Test
    fun `CIProvider enum has all expected values`() {
        val providers = CIProvider.entries
        assertEquals(6, providers.size)
        assertTrue(providers.contains(CIProvider.GITHUB))
        assertTrue(providers.contains(CIProvider.GITLAB))
        assertTrue(providers.contains(CIProvider.CIRCLECI))
        assertTrue(providers.contains(CIProvider.BUILDKITE))
        assertTrue(providers.contains(CIProvider.CODEMAGIC))
        assertTrue(providers.contains(CIProvider.BITRISE))
    }
}

class DiscoverTestSuitesTest {

    @Test
    fun `discovers test classes from compiled output`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/SignupTest.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest", "com.example.SignupTest"), suites)
    }

    @Test
    fun `excludes inner classes`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/LoginTest\$Companion.class").createNewFile()
        File(classesDir, "com/example/LoginTest\$nested.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest"), suites)
    }

    @Test
    fun `excludes non-class files`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")

        File(classesDir, "com/example").mkdirs()
        File(classesDir, "com/example/LoginTest.class").createNewFile()
        File(classesDir, "com/example/README.txt").createNewFile()
        File(classesDir, "com/example/data.json").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertEquals(listOf("com.example.LoginTest"), suites)
    }

    @Test
    fun `returns empty list for empty directory`(@TempDir tempDir: File) {
        val classesDir = File(tempDir, "build/classes/kotlin/test")
        classesDir.mkdirs()

        val suites = discoverTestSuitesFromDirs(listOf(classesDir))

        assertTrue(suites.isEmpty())
    }

    @Test
    fun `handles multiple class directories`(@TempDir tempDir: File) {
        val dir1 = File(tempDir, "module1/build/classes/kotlin/test")
        val dir2 = File(tempDir, "module2/build/classes/kotlin/test")

        File(dir1, "com/example").mkdirs()
        File(dir1, "com/example/Test1.class").createNewFile()
        File(dir2, "com/other").mkdirs()
        File(dir2, "com/other/Test2.class").createNewFile()

        val suites = discoverTestSuitesFromDirs(listOf(dir1, dir2))

        assertEquals(listOf("com.example.Test1", "com.other.Test2"), suites)
    }
}
