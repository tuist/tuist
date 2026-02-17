package dev.tuist.gradle

import com.google.gson.Gson
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
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
                override fun getConfiguration(forceRefresh: Boolean) = TuistCacheConfiguration(
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
                override fun getConfiguration(forceRefresh: Boolean) = TuistCacheConfiguration(
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
}
