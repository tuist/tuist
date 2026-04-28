package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.gradle.api.tasks.testing.TestResult
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TuistTestQuarantineTest {

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

    private fun createService(): TuistTestQuarantineService {
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
        return TuistTestQuarantineService(httpClient = httpClient, baseUrl = baseUrl)
    }

    @Test
    fun `getQuarantinedTests groups muted tests by module`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testLogin",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.LoginTest"),
                        state = "muted"
                    ),
                    QuarantinedTestCase(
                        name = "testLogout",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "2", name = "com.example.LogoutTest"),
                        state = "muted"
                    ),
                    QuarantinedTestCase(
                        name = "testParse",
                        module = QuarantinedModule(id = "2", name = ":lib"),
                        suite = QuarantinedSuite(id = "3", name = "com.example.ParserTest"),
                        state = "muted"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(2, result.muted.size)
        assertTrue(result.skipped.isEmpty())
        assertEquals(
            listOf(
                TestIdentifier("com.example.LoginTest", "testLogin"),
                TestIdentifier("com.example.LogoutTest", "testLogout")
            ),
            result.muted[":app"]
        )
        assertEquals(
            listOf(TestIdentifier("com.example.ParserTest", "testParse")),
            result.muted[":lib"]
        )
    }

    @Test
    fun `getQuarantinedTests splits muted and skipped tests by mode`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testFlaky",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.FooTest"),
                        state = "muted"
                    ),
                    QuarantinedTestCase(
                        name = "testBroken",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "2", name = "com.example.BarTest"),
                        state = "skipped"
                    ),
                    QuarantinedTestCase(
                        name = "testSlow",
                        module = QuarantinedModule(id = "2", name = ":lib"),
                        suite = QuarantinedSuite(id = "3", name = "com.example.SlowTest"),
                        state = "skipped"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(
            listOf(TestIdentifier("com.example.FooTest", "testFlaky")),
            result.muted[":app"]
        )
        assertEquals(
            listOf(TestIdentifier("com.example.BarTest", "testBroken")),
            result.skipped[":app"]
        )
        assertEquals(
            listOf(TestIdentifier("com.example.SlowTest", "testSlow")),
            result.skipped[":lib"]
        )
        assertFalse(result.muted.containsKey(":lib"))
    }

    @Test
    fun `getQuarantinedTests treats null state as muted for back-compat`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testLegacy",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.LegacyTest"),
                        state = null
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(
            listOf(TestIdentifier("com.example.LegacyTest", "testLegacy")),
            result.muted[":app"]
        )
        assertTrue(result.skipped.isEmpty())
    }

    @Test
    fun `getQuarantinedTests uses null suite for null suite`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testDynamic",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = null,
                        state = "muted"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(listOf(TestIdentifier(null, "testDynamic")), result.muted[":app"])
    }

    @Test
    fun `getQuarantinedTests uses null suite for blank suite name`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testBlank",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "  "),
                        state = "muted"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(listOf(TestIdentifier(null, "testBlank")), result.muted[":app"])
    }

    @Test
    fun `getQuarantinedTests parses API response`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testFlaky",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.FlakyTest"),
                        state = "muted"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertEquals(1, result.muted.size)
        assertEquals(
            listOf(TestIdentifier("com.example.FlakyTest", "testFlaky")),
            result.muted[":app"]
        )

        val request = mockWebServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.contains("/api/projects/test-account/test-project/tests/test-cases"))
        assertTrue(request.path!!.contains("quarantined=true"))
    }

    @Test
    fun `getQuarantinedTests returns empty result on network error`() {
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
        val service = TuistTestQuarantineService(httpClient = httpClient, baseUrl = baseUrl)

        val result = service.getQuarantinedTests()

        assertTrue(result.isEmpty())
    }

    @Test
    fun `getQuarantinedTests returns empty result on non-200 response`() {
        val service = createService()

        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        val result = service.getQuarantinedTests()

        assertTrue(result.isEmpty())
    }

    @Test
    fun `getQuarantinedTests caches result across multiple calls`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testCached",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.CachedTest"),
                        state = "muted"
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val first = service.getQuarantinedTests()
        val second = service.getQuarantinedTests()
        val third = service.getQuarantinedTests()

        assertEquals(first, second)
        assertEquals(second, third)
        assertEquals(1, mockWebServer.requestCount)
    }

    @Test
    fun `getQuarantinedTests handles empty test cases list`() {
        val service = createService()

        val responseBody = Gson().toJson(QuarantinedTestCasesResponse(testCases = emptyList()))
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val result = service.getQuarantinedTests()

        assertTrue(result.isEmpty())
    }

    @Test
    fun `QuarantinedTests all unions muted and skipped per module`() {
        val muted = mapOf(
            ":app" to listOf(TestIdentifier("FooTest", "testFlaky"))
        )
        val skipped = mapOf(
            ":app" to listOf(TestIdentifier("BarTest", "testBroken")),
            ":lib" to listOf(TestIdentifier("SlowTest", "testSlow"))
        )

        val all = QuarantinedTests(muted = muted, skipped = skipped).all

        assertEquals(
            listOf(
                TestIdentifier("FooTest", "testFlaky"),
                TestIdentifier("BarTest", "testBroken")
            ),
            all[":app"]
        )
        assertEquals(
            listOf(TestIdentifier("SlowTest", "testSlow")),
            all[":lib"]
        )
    }

    @Test
    fun `TestIdentifier matches by suite and name`() {
        val id = TestIdentifier("com.example.FooTest", "testLogin")
        assertTrue(id.matches("com.example.FooTest", "testLogin"))
        assertFalse(id.matches("com.example.BarTest", "testLogin"))
        assertFalse(id.matches("com.example.FooTest", "testLogout"))
    }

    @Test
    fun `TestIdentifier with null suite matches any class`() {
        val id = TestIdentifier(null, "testLogin")
        assertTrue(id.matches("com.example.FooTest", "testLogin"))
        assertTrue(id.matches("com.example.BarTest", "testLogin"))
        assertFalse(id.matches("com.example.FooTest", "testLogout"))
    }

    @Test
    fun `hasNonQuarantinedFailures returns false when no tests`() {
        val collector = TestReportCollector()
        assertFalse(collector.hasNonQuarantinedFailures(":app"))
    }

    @Test
    fun `hasNonQuarantinedFailures returns false when only quarantined tests fail`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testFail", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null, isQuarantined = true)
        collector.collectTestResult(":app", "testPass", "com.example.FooTest", TestResult.ResultType.SUCCESS, 0, 100, null)

        assertFalse(collector.hasNonQuarantinedFailures(":app"))
    }

    @Test
    fun `hasNonQuarantinedFailures returns true when non-quarantined test fails`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testFail", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null, isQuarantined = false)

        assertTrue(collector.hasNonQuarantinedFailures(":app"))
    }

    @Test
    fun `hasNonQuarantinedFailures returns true for mixed failures`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testQuarantined", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null, isQuarantined = true)
        collector.collectTestResult(":app", "testReal", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null, isQuarantined = false)

        assertTrue(collector.hasNonQuarantinedFailures(":app"))
    }
}
