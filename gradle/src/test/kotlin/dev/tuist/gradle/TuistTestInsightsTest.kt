package dev.tuist.gradle

import com.google.gson.Gson
import org.junit.jupiter.api.Test
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class TestGitInfoProviderForTests(
    private val branch: String? = null,
    private val commitSha: String? = null,
    private val ref: String? = null
) : GitInfoProvider {
    override fun branch(): String? = branch
    override fun commitSha(): String? = commitSha
    override fun ref(): String? = ref
}

private class TestCIDetectorForTests(private val isCi: Boolean = false) : CIDetector {
    override fun isCi(): Boolean = isCi
}

class TuistTestInsightsTest {

    private val gson = Gson()

    @Test
    fun `TestReportRequest serializes with snake_case field names`() {
        val report = TestReportRequest(
            duration = 5000,
            status = "success",
            isCi = true,
            scheme = "my-app",
            gitBranch = "main",
            gitCommitSha = "abc",
            gitRef = "v1",
            testModules = emptyList()
        )

        val json = gson.toJson(report)
        assertTrue(json.contains("\"is_ci\""))
        assertTrue(json.contains("\"build_system\""))
        assertTrue(json.contains("\"macos_version\""))
        assertTrue(json.contains("\"xcode_version\""))
        assertTrue(json.contains("\"model_identifier\""))
        assertTrue(json.contains("\"git_branch\""))
        assertTrue(json.contains("\"git_commit_sha\""))
        assertTrue(json.contains("\"git_ref\""))
        assertTrue(json.contains("\"test_modules\""))
        assertTrue(!json.contains("\"isCi\""))
        assertTrue(!json.contains("\"buildSystem\""))
    }

    @Test
    fun `TestReportRequest defaults build_system to gradle`() {
        val report = TestReportRequest(
            duration = 1000,
            status = "success",
            isCi = false,
            scheme = null,
            gitBranch = null,
            gitCommitSha = null,
            gitRef = null,
            testModules = emptyList()
        )

        assertEquals("gradle", report.buildSystem)
        assertEquals("", report.macosVersion)
        assertEquals("", report.xcodeVersion)
        assertEquals("", report.modelIdentifier)
    }

    @Test
    fun `TestModuleReport serializes correctly`() {
        val module = TestModuleReport(
            name = ":app",
            status = "failure",
            duration = 3000,
            testSuites = listOf(
                TestSuiteReport(name = "com.example.LoginTest", status = "failure", duration = 2000)
            ),
            testCases = listOf(
                TestCaseReport(
                    name = "testLogin",
                    testSuiteName = "com.example.LoginTest",
                    status = "failure",
                    duration = 1500,
                    failures = listOf(
                        TestFailureReport(
                            message = "Expected true but was false",
                            path = "LoginTest.kt",
                            lineNumber = 42,
                            issueType = "assertion_failure"
                        )
                    )
                )
            )
        )

        val json = gson.toJson(module)
        assertTrue(json.contains("\"test_suites\""))
        assertTrue(json.contains("\"test_cases\""))
        assertTrue(json.contains("\"test_suite_name\""))
        assertTrue(json.contains("\"line_number\""))
        assertTrue(json.contains("\"issue_type\""))
    }

    @Test
    fun `TestFailureReport serializes with snake_case`() {
        val failure = TestFailureReport(
            message = "Something went wrong",
            path = "MyTest.kt",
            lineNumber = 10,
            issueType = "error_thrown"
        )

        val json = gson.toJson(failure)
        assertTrue(json.contains("\"line_number\""))
        assertTrue(json.contains("\"issue_type\""))
        assertTrue(!json.contains("\"lineNumber\""))
        assertTrue(!json.contains("\"issueType\""))
    }

    @Test
    fun `URL construction for test endpoint is correct`() {
        val baseUrl = "https://tuist.dev"
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$baseUrl/api/$accountHandle/$projectHandle/tests")

        assertEquals("https", url.scheme)
        assertEquals("tuist.dev", url.host)
        assertEquals("/api/my-org/my-project/tests", url.path)
    }

    @Test
    fun `URL construction with trailing slash`() {
        val baseUrl = "https://tuist.dev/".trimEnd('/')
        val accountHandle = "my-org"
        val projectHandle = "my-project"

        val url = URI("$baseUrl/api/$accountHandle/$projectHandle/tests")

        assertEquals("/api/my-org/my-project/tests", url.path)
    }

    @Test
    fun `CollectedTestModule aggregates test case data`() {
        val module = CollectedTestModule(name = ":app")

        module.testCases.add(CollectedTestCase("test1", "Suite1", "success", 100, emptyList()))
        module.testCases.add(CollectedTestCase("test2", "Suite1", "failure", 200, listOf(
            TestFailureReport("fail", "Test.kt", 5, "assertion_failure")
        )))
        module.durationMs = 300
        module.status = "failure"

        assertEquals(2, module.testCases.size)
        assertEquals("failure", module.status)
        assertEquals(300, module.durationMs)
    }

    @Test
    fun `CollectedTestSuite tracks status and duration`() {
        val suite = CollectedTestSuite(name = "com.example.MyTest")

        suite.durationMs += 100
        suite.durationMs += 200
        suite.status = "failure"

        assertEquals(300, suite.durationMs)
        assertEquals("failure", suite.status)
    }
}
