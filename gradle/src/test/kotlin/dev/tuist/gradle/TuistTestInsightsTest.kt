package dev.tuist.gradle

import com.google.gson.Gson
import org.gradle.api.tasks.testing.TestResult
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

    // --- Data class serialization tests ---

    @Test
    fun `TestReport serializes with snake_case field names`() {
        val report = TestReport(
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
        assertTrue(json.contains("\"git_branch\""))
        assertTrue(json.contains("\"git_commit_sha\""))
        assertTrue(json.contains("\"git_ref\""))
        assertTrue(json.contains("\"test_modules\""))
        assertTrue(!json.contains("\"isCi\""))
        assertTrue(!json.contains("\"buildSystem\""))
    }

    @Test
    fun `TestReport defaults build_system to gradle`() {
        val report = TestReport(
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
    }

    @Test
    fun `TestModule serializes correctly`() {
        val module = TestModule(
            name = ":app",
            status = "failure",
            duration = 3000,
            testSuites = listOf(
                TestSuite(name = "com.example.LoginTest", status = "failure", duration = 2000)
            ),
            testCases = listOf(
                TestCase(
                    name = "testLogin",
                    testSuiteName = "com.example.LoginTest",
                    status = "failure",
                    duration = 1500,
                    failures = listOf(
                        TestFailure(
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
    fun `TestFailure serializes with snake_case`() {
        val failure = TestFailure(
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

    // --- collectTestResult tests ---

    @Test
    fun `collectTestResult adds passing test to module`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testLogin", "com.example.LoginTest",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )

        assertEquals(1, testCasesByModule.size)
        val cases = testCasesByModule[":app"]!!
        assertEquals(1, cases.size)
        assertEquals("testLogin", cases[0].name)
        assertEquals("com.example.LoginTest", cases[0].testSuiteName)
        assertEquals("success", cases[0].status)
        assertEquals(100, cases[0].duration)
        assertTrue(cases[0].failures.isEmpty())
    }

    @Test
    fun `collectTestResult accumulates test cases in same module`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.SuiteA",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":app", "testB", "com.example.SuiteA",
            TestResult.ResultType.SUCCESS, 100, 350, null
        )

        val cases = testCasesByModule[":app"]!!
        assertEquals(2, cases.size)
        assertEquals(100, cases[0].duration)
        assertEquals(250, cases[1].duration)
    }

    @Test
    fun `collectTestResult records failure status on test case`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.SuiteA",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":app", "testB", "com.example.SuiteA",
            TestResult.ResultType.FAILURE, 100, 200, RuntimeException("fail")
        )

        val cases = testCasesByModule[":app"]!!
        assertEquals("success", cases[0].status)
        assertEquals("failure", cases[1].status)
    }

    @Test
    fun `collectTestResult handles multiple modules`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.AppTest",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":lib", "testB", "com.example.LibTest",
            TestResult.ResultType.SUCCESS, 0, 200, null
        )

        assertEquals(2, testCasesByModule.size)
        assertEquals(1, testCasesByModule[":app"]!!.size)
        assertEquals(1, testCasesByModule[":lib"]!!.size)
    }

    @Test
    fun `collectTestResult handles test with null className`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testDynamic", null,
            TestResult.ResultType.SUCCESS, 0, 50, null
        )

        val cases = testCasesByModule[":app"]!!
        assertEquals(1, cases.size)
        assertNull(cases[0].testSuiteName)
    }

    @Test
    fun `collectTestResult handles skipped test`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testSkipped", "com.example.Test",
            TestResult.ResultType.SKIPPED, 0, 0, null
        )

        val cases = testCasesByModule[":app"]!!
        assertEquals("skipped", cases[0].status)
    }

    @Test
    fun `collectTestResult attaches assertion failure with user frame from stack trace`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        val exception = AssertionError("expected 1 but got 2")
        exception.stackTrace = arrayOf(
            StackTraceElement("org.junit.jupiter.api.AssertionUtils", "fail", "AssertionUtils.java", 55),
            StackTraceElement("java.lang.reflect.Method", "invoke", "Method.java", 566),
            StackTraceElement("com.example.MathTest", "testAdd", "MathTest.kt", 15),
            StackTraceElement("com.example.MathTest", "setup", "MathTest.kt", 5)
        )

        collectTestResult(
            testCasesByModule, ":app", "testAdd", "com.example.MathTest",
            TestResult.ResultType.FAILURE, 0, 50, exception
        )

        val testCase = testCasesByModule[":app"]!![0]
        assertEquals(1, testCase.failures.size)
        assertEquals("assertion_failure", testCase.failures[0].issueType)
        assertEquals("MathTest.kt", testCase.failures[0].path)
        assertEquals(15, testCase.failures[0].lineNumber)
    }

    @Test
    fun `collectTestResult classifies runtime exception as error_thrown`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        val exception = RuntimeException("something went wrong")
        exception.stackTrace = arrayOf(
            StackTraceElement("com.example.MyTest", "testSomething", "MyTest.kt", 42)
        )

        collectTestResult(
            testCasesByModule, ":app", "testSomething", "com.example.MyTest",
            TestResult.ResultType.FAILURE, 0, 100, exception
        )

        val testCase = testCasesByModule[":app"]!![0]
        assertEquals("error_thrown", testCase.failures[0].issueType)
        assertEquals("something went wrong", testCase.failures[0].message)
    }

    @Test
    fun `collectTestResult produces default failure when exception is null`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testFail", "com.example.Test",
            TestResult.ResultType.FAILURE, 0, 100, null
        )

        val testCase = testCasesByModule[":app"]!![0]
        assertEquals(1, testCase.failures.size)
        assertEquals("Test failed", testCase.failures[0].message)
        assertNull(testCase.failures[0].path)
        assertEquals(0, testCase.failures[0].lineNumber)
        assertEquals("error_thrown", testCase.failures[0].issueType)
    }

    // --- buildTestReport tests ---

    @Test
    fun `buildTestReport builds report from empty modules`() {
        val report = buildTestReport(
            testCasesByModule = emptyMap(),
            totalDurationMs = 5000,
            isCi = false,
            scheme = "my-app",
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v1.0",
            gradleBuildId = null
        )

        assertEquals(5000, report.duration)
        assertEquals("success", report.status)
        assertEquals(false, report.isCi)
        assertEquals("my-app", report.scheme)
        assertEquals("gradle", report.buildSystem)
        assertEquals("main", report.gitBranch)
        assertEquals("abc123", report.gitCommitSha)
        assertEquals("v1.0", report.gitRef)
        assertNull(report.gradleBuildId)
        assertTrue(report.testModules.isEmpty())
    }

    @Test
    fun `buildTestReport sets status to failure when any module failed`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":lib", "testB", "com.example.Test",
            TestResult.ResultType.FAILURE, 0, 200, null
        )

        val report = buildTestReport(
            testCasesByModule, 5000, false, null, null, null, null, null
        )

        assertEquals("failure", report.status)
    }

    @Test
    fun `buildTestReport sets status to success when all pass`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":lib", "testB", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 200, null
        )

        val report = buildTestReport(
            testCasesByModule, 5000, false, null, null, null, null, null
        )

        assertEquals("success", report.status)
    }

    @Test
    fun `buildTestReport maps module data to report`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        collectTestResult(
            testCasesByModule, ":app", "testLogin", "com.example.LoginTest",
            TestResult.ResultType.SUCCESS, 0, 150, null
        )
        collectTestResult(
            testCasesByModule, ":app", "testLogout", "com.example.LoginTest",
            TestResult.ResultType.FAILURE, 150, 300, RuntimeException("timeout")
        )

        val report = buildTestReport(
            testCasesByModule, 5000, true, "my-app", "feature/auth", "def456", null, "build-123"
        )

        assertEquals(1, report.testModules.size)
        val appModule = report.testModules[0]
        assertEquals(":app", appModule.name)
        assertEquals("failure", appModule.status)
        assertEquals(300, appModule.duration)

        assertEquals(1, appModule.testSuites.size)
        assertEquals("com.example.LoginTest", appModule.testSuites[0].name)
        assertEquals("failure", appModule.testSuites[0].status)
        assertEquals(300, appModule.testSuites[0].duration)

        assertEquals(2, appModule.testCases.size)
        assertEquals("testLogin", appModule.testCases[0].name)
        assertEquals("com.example.LoginTest", appModule.testCases[0].testSuiteName)
        assertEquals("success", appModule.testCases[0].status)
        assertTrue(appModule.testCases[0].failures.isEmpty())

        assertEquals("testLogout", appModule.testCases[1].name)
        assertEquals("failure", appModule.testCases[1].status)
        assertEquals(1, appModule.testCases[1].failures.size)

        assertEquals(true, report.isCi)
        assertEquals("my-app", report.scheme)
        assertEquals("feature/auth", report.gitBranch)
        assertEquals("def456", report.gitCommitSha)
        assertEquals("build-123", report.gradleBuildId)
    }

    @Test
    fun `buildTestReport handles multiple suites within a module`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()
        collectTestResult(
            testCasesByModule, ":app", "testA", "com.example.SuiteA",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":app", "testB", "com.example.SuiteB",
            TestResult.ResultType.SUCCESS, 0, 200, null
        )

        val report = buildTestReport(
            testCasesByModule, 5000, false, null, null, null, null, null
        )

        val appModule = report.testModules[0]
        assertEquals(2, appModule.testSuites.size)
        val suiteNames = appModule.testSuites.map { it.name }.toSet()
        assertTrue(suiteNames.contains("com.example.SuiteA"))
        assertTrue(suiteNames.contains("com.example.SuiteB"))
    }

    // --- End-to-end collection + report flow ---

    @Test
    fun `end-to-end collection and report for multi-module project`() {
        val testCasesByModule = mutableMapOf<String, MutableList<TestCase>>()

        collectTestResult(
            testCasesByModule, ":app", "testLogin", "com.example.LoginTest",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collectTestResult(
            testCasesByModule, ":app", "testRegister", "com.example.RegisterTest",
            TestResult.ResultType.SUCCESS, 100, 250, null
        )
        collectTestResult(
            testCasesByModule, ":lib", "testParse", "com.example.ParserTest",
            TestResult.ResultType.FAILURE, 0, 50,
            AssertionError("expected 42 but was 0").apply {
                stackTrace = arrayOf(
                    StackTraceElement("org.junit.jupiter.api.Assertions", "assertEquals", "Assertions.java", 150),
                    StackTraceElement("com.example.ParserTest", "testParse", "ParserTest.kt", 28)
                )
            }
        )

        val report = buildTestReport(
            testCasesByModule = testCasesByModule,
            totalDurationMs = 10000,
            isCi = true,
            scheme = "android-app",
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v2.0",
            gradleBuildId = "build-456"
        )

        assertEquals("failure", report.status)
        assertEquals(10000, report.duration)
        assertEquals(true, report.isCi)
        assertEquals("android-app", report.scheme)
        assertEquals("build-456", report.gradleBuildId)
        assertEquals(2, report.testModules.size)

        val appModule = report.testModules.first { it.name == ":app" }
        assertEquals("success", appModule.status)
        assertEquals(250, appModule.duration)
        assertEquals(2, appModule.testSuites.size)
        assertEquals(2, appModule.testCases.size)

        val libModule = report.testModules.first { it.name == ":lib" }
        assertEquals("failure", libModule.status)
        assertEquals(50, libModule.duration)
        assertEquals(1, libModule.testCases.size)

        val failedCase = libModule.testCases[0]
        assertEquals("testParse", failedCase.name)
        assertEquals("failure", failedCase.status)
        assertEquals(1, failedCase.failures.size)
        assertEquals("assertion_failure", failedCase.failures[0].issueType)
        assertEquals("ParserTest.kt", failedCase.failures[0].path)
        assertEquals(28, failedCase.failures[0].lineNumber)
    }
}
