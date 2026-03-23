package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
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
    fun `getQuarantinedTests groups tests by module`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testLogin",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "com.example.LoginTest")
                    ),
                    QuarantinedTestCase(
                        name = "testLogout",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "2", name = "com.example.LogoutTest")
                    ),
                    QuarantinedTestCase(
                        name = "testParse",
                        module = QuarantinedModule(id = "2", name = ":lib"),
                        suite = QuarantinedSuite(id = "3", name = "com.example.ParserTest")
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val exclusions = service.getQuarantinedTests()

        assertEquals(2, exclusions.size)
        assertEquals(
            listOf("com.example.LoginTest.testLogin", "com.example.LogoutTest.testLogout"),
            exclusions[":app"]
        )
        assertEquals(
            listOf("com.example.ParserTest.testParse"),
            exclusions[":lib"]
        )
    }

    @Test
    fun `getQuarantinedTests uses wildcard for null suite`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testDynamic",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = null
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val exclusions = service.getQuarantinedTests()

        assertEquals(listOf("*.testDynamic"), exclusions[":app"])
    }

    @Test
    fun `getQuarantinedTests uses wildcard for blank suite name`() {
        val service = createService()

        val responseBody = Gson().toJson(
            QuarantinedTestCasesResponse(
                testCases = listOf(
                    QuarantinedTestCase(
                        name = "testBlank",
                        module = QuarantinedModule(id = "1", name = ":app"),
                        suite = QuarantinedSuite(id = "1", name = "  ")
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val exclusions = service.getQuarantinedTests()

        assertEquals(listOf("*.testBlank"), exclusions[":app"])
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
                        suite = QuarantinedSuite(id = "1", name = "com.example.FlakyTest")
                    )
                )
            )
        )
        mockWebServer.enqueue(MockResponse().setResponseCode(200).setBody(responseBody))

        val exclusions = service.getQuarantinedTests()

        assertEquals(1, exclusions.size)
        assertEquals(listOf("com.example.FlakyTest.testFlaky"), exclusions[":app"])

        val request = mockWebServer.takeRequest()
        assertEquals("GET", request.method)
        assertTrue(request.path!!.contains("/api/projects/test-account/test-project/tests/test-cases"))
        assertTrue(request.path!!.contains("quarantined=true"))
    }

    @Test
    fun `getQuarantinedTests returns empty map on network error`() {
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

        val exclusions = service.getQuarantinedTests()

        assertTrue(exclusions.isEmpty())
    }

    @Test
    fun `getQuarantinedTests returns empty map on non-200 response`() {
        val service = createService()

        mockWebServer.enqueue(MockResponse().setResponseCode(500).setBody("Internal Server Error"))

        val exclusions = service.getQuarantinedTests()

        assertTrue(exclusions.isEmpty())
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
                        suite = QuarantinedSuite(id = "1", name = "com.example.CachedTest")
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

        val exclusions = service.getQuarantinedTests()

        assertTrue(exclusions.isEmpty())
    }

    @Test
    fun `matchesQuarantinePattern matches exact pattern`() {
        assertTrue(matchesQuarantinePattern("com.example.LoginTest.testLogin", "com.example.LoginTest.testLogin"))
    }

    @Test
    fun `matchesQuarantinePattern does not match different pattern`() {
        assertFalse(matchesQuarantinePattern("com.example.LoginTest.testLogin", "com.example.LoginTest.testLogout"))
    }

    @Test
    fun `matchesQuarantinePattern matches wildcard pattern`() {
        assertTrue(matchesQuarantinePattern("com.example.LoginTest.testDynamic", "*.testDynamic"))
    }

    @Test
    fun `matchesQuarantinePattern wildcard does not match wrong method`() {
        assertFalse(matchesQuarantinePattern("com.example.LoginTest.testLogin", "*.testDynamic"))
    }

    @Test
    fun `getFailedTestIdentifiers returns empty for unknown module`() {
        val collector = TestReportCollector()
        assertEquals(emptyList(), collector.getFailedTestIdentifiers(":app"))
    }

    @Test
    fun `getFailedTestIdentifiers returns only failed tests`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testPass", "com.example.FooTest", TestResult.ResultType.SUCCESS, 0, 100, null)
        collector.collectTestResult(":app", "testFail", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null)
        collector.collectTestResult(":app", "testSkip", "com.example.FooTest", TestResult.ResultType.SKIPPED, 0, 100, null)

        val failed = collector.getFailedTestIdentifiers(":app")
        assertEquals(listOf("com.example.FooTest.testFail"), failed)
    }

    @Test
    fun `getFailedTestIdentifiers uses wildcard for null className`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testDynamic", null, TestResult.ResultType.FAILURE, 0, 100, null)

        val failed = collector.getFailedTestIdentifiers(":app")
        assertEquals(listOf("*.testDynamic"), failed)
    }

    @Test
    fun `getFailedTestIdentifiers deduplicates results`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testFlaky", "com.example.FooTest", TestResult.ResultType.FAILURE, 0, 100, null)
        collector.collectTestResult(":app", "testFlaky", "com.example.FooTest", TestResult.ResultType.FAILURE, 100, 200, null)

        val failed = collector.getFailedTestIdentifiers(":app")
        assertEquals(listOf("com.example.FooTest.testFlaky"), failed)
    }

    @Test
    fun `real failures are detected when quarantine map matches some`() {
        val allFailed = listOf(
            "com.example.LoginTest.testLogin",
            "com.example.SignupTest.testSignup"
        )
        val quarantinePatterns = listOf("com.example.LoginTest.testLogin")

        val realFailures = allFailed.filter { testId ->
            !quarantinePatterns.any { pattern -> matchesQuarantinePattern(testId, pattern) }
        }

        assertEquals(listOf("com.example.SignupTest.testSignup"), realFailures)
    }

    @Test
    fun `no real failures when all failed tests are quarantined`() {
        val allFailed = listOf(
            "com.example.LoginTest.testLogin",
            "com.example.LogoutTest.testLogout"
        )
        val quarantinePatterns = listOf(
            "com.example.LoginTest.testLogin",
            "com.example.LogoutTest.testLogout"
        )

        val realFailures = allFailed.filter { testId ->
            !quarantinePatterns.any { pattern -> matchesQuarantinePattern(testId, pattern) }
        }

        assertTrue(realFailures.isEmpty())
    }
}
