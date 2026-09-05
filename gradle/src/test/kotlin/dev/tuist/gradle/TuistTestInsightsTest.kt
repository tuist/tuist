package dev.tuist.gradle

import org.gradle.api.tasks.testing.TestResult
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TuistTestInsightsTest {

    @Test
    fun `buildReport builds report from empty collector`() {
        val collector = TestReportCollector()

        val report = collector.buildReport(
            totalDurationMs = 5000,
            isCi = false,
            scheme = "my-app",
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v1.0",
            gitRemoteUrlOrigin = "https://github.com/tuist/tuist.git",
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
        assertEquals("https://github.com/tuist/tuist.git", report.gitRemoteUrlOrigin)
        assertNull(report.gradleBuildId)
        assertTrue(report.testModules.isEmpty())
    }

    @Test
    fun `repetitionResults keeps a skipped rerun skipped`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testNew", "com.example.NewTest", TestResult.ResultType.SKIPPED, 0, 5, null)

        assertEquals(listOf("skipped"), collector.repetitionResults().map { it.status })
    }

    @Test
    fun `buildReport reports the stress gate's reruns with the test case they belong to`() {
        val collector = TestReportCollector()
        collector.collectTestResult(":app", "testNew", "com.example.NewTest", TestResult.ResultType.SUCCESS, 0, 10, null)
        collector.collectTestResult(":app", "testNew", "com.example.OtherTest", TestResult.ResultType.SUCCESS, 10, 20, null)

        val stress = StressNewTestsReport(
            mode = "report",
            outcome = "disagreed",
            newCount = 1,
            stressedCount = 1,
            excludedCount = 0,
            inventoryCount = 40,
            testCases = listOf(
                StressNewTestsCandidateReport(
                    name = "testNew",
                    suiteName = "com.example.NewTest",
                    moduleName = ":app",
                    repetitions = 2,
                    failedRepetitions = 1,
                    outcome = "disagreed",
                    isQuarantined = false,
                    repetitionResults = listOf(
                        StressRepetitionReport(1, "success", 4, null),
                        StressRepetitionReport(2, "failure", 5, StressRepetitionFailure("boom", "assertion_failure"))
                    )
                )
            )
        )

        val report = collector.buildReport(30, true, "my-app", "feature", "abc", null, null, null, stressNewTests = stress)

        val cases = report.testModules.single().testCases.associateBy { it.testSuiteName }
        val stressed = cases.getValue("com.example.NewTest")
        assertEquals(listOf("Stress 1", "Stress 2"), stressed.repetitions!!.map { it.name })
        assertEquals(listOf("stress", "stress"), stressed.repetitions!!.map { it.source })
        assertEquals(listOf(1, 2), stressed.repetitions!!.map { it.repetitionNumber })
        assertEquals(listOf("boom"), stressed.failures.map { it.message })

        // The same method name in another suite is another test case.
        assertNull(cases.getValue("com.example.OtherTest").repetitions)
    }

    @Test
    fun `buildReport sets status to failure when any module failed`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testA", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collector.collectTestResult(
            ":lib", "testB", "com.example.Test",
            TestResult.ResultType.FAILURE, 0, 200, null
        )

        val report = collector.buildReport(5000, false, null, null, null, null, null, null)

        assertEquals("failure", report.status)
    }

    @Test
    fun `buildReport sets status to success when all pass`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testA", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collector.collectTestResult(
            ":lib", "testB", "com.example.Test",
            TestResult.ResultType.SUCCESS, 0, 200, null
        )

        val report = collector.buildReport(5000, false, null, null, null, null, null, null)

        assertEquals("success", report.status)
    }

    @Test
    fun `buildReport maps module data to report`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testLogin", "com.example.LoginTest",
            TestResult.ResultType.SUCCESS, 0, 150, null
        )
        collector.collectTestResult(
            ":app", "testLogout", "com.example.LoginTest",
            TestResult.ResultType.FAILURE, 150, 300, RuntimeException("timeout")
        )

        val report = collector.buildReport(5000, true, "my-app", "feature/auth", "def456", null, null, "build-123")

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
    fun `buildReport handles multiple suites within a module`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testA", "com.example.SuiteA",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collector.collectTestResult(
            ":app", "testB", "com.example.SuiteB",
            TestResult.ResultType.SUCCESS, 0, 200, null
        )

        val report = collector.buildReport(5000, false, null, null, null, null, null, null)

        val appModule = report.testModules[0]
        assertEquals(2, appModule.testSuites.size)
        val suiteNames = appModule.testSuites.map { it.name }.toSet()
        assertTrue(suiteNames.contains("com.example.SuiteA"))
        assertTrue(suiteNames.contains("com.example.SuiteB"))
    }

    @Test
    fun `buildReport excludes suites for tests with null className`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testDynamic", null,
            TestResult.ResultType.SUCCESS, 0, 50, null
        )

        val report = collector.buildReport(50, false, null, null, null, null, null, null)

        val appModule = report.testModules[0]
        assertEquals(1, appModule.testCases.size)
        assertNull(appModule.testCases[0].testSuiteName)
        assertTrue(appModule.testSuites.isEmpty())
    }

    @Test
    fun `buildReport maps skipped tests correctly`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            ":app", "testSkipped", "com.example.Test",
            TestResult.ResultType.SKIPPED, 0, 0, null
        )

        val report = collector.buildReport(0, false, null, null, null, null, null, null)

        assertEquals("skipped", report.testModules[0].testCases[0].status)
    }

    @Test
    fun `buildReport classifies runtime exception as error_thrown`() {
        val collector = TestReportCollector()
        val exception = RuntimeException("something went wrong")
        exception.stackTrace = arrayOf(
            StackTraceElement("com.example.MyTest", "testSomething", "MyTest.kt", 42)
        )

        collector.collectTestResult(
            ":app", "testSomething", "com.example.MyTest",
            TestResult.ResultType.FAILURE, 0, 100, exception
        )

        val report = collector.buildReport(100, false, null, null, null, null, null, null)
        val testCase = report.testModules[0].testCases[0]
        assertEquals("error_thrown", testCase.failures[0].issueType)
        assertEquals("something went wrong", testCase.failures[0].message)
    }

    @Test
    fun `buildReport produces default failure when exception is null`() {
        val collector = TestReportCollector()

        collector.collectTestResult(
            ":app", "testFail", "com.example.Test",
            TestResult.ResultType.FAILURE, 0, 100, null
        )

        val report = collector.buildReport(100, false, null, null, null, null, null, null)
        val testCase = report.testModules[0].testCases[0]
        assertEquals(1, testCase.failures.size)
        assertEquals("Test failed", testCase.failures[0].message)
        assertNull(testCase.failures[0].path)
        assertEquals(0, testCase.failures[0].lineNumber)
        assertEquals("error_thrown", testCase.failures[0].issueType)
    }

    @Test
    fun `buildReport uses project name as module for single-module project`() {
        val collector = TestReportCollector()
        collector.collectTestResult(
            "my-gradle-plugin", "testApply", "dev.tuist.gradle.PluginTest",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collector.collectTestResult(
            "my-gradle-plugin", "testConfig", "dev.tuist.gradle.ConfigTest",
            TestResult.ResultType.SUCCESS, 100, 250, null
        )

        val report = collector.buildReport(250, false, "my-gradle-plugin", "main", "abc123", null, null, null)

        assertEquals(1, report.testModules.size)
        val module = report.testModules[0]
        assertEquals("my-gradle-plugin", module.name)
        assertEquals("success", module.status)
        assertEquals(250, module.duration)
        assertEquals(2, module.testSuites.size)
        assertEquals(2, module.testCases.size)
    }

    @Test
    fun `end-to-end collection and report for multi-module project`() {
        val collector = TestReportCollector()

        collector.collectTestResult(
            ":app", "testLogin", "com.example.LoginTest",
            TestResult.ResultType.SUCCESS, 0, 100, null
        )
        collector.collectTestResult(
            ":app", "testRegister", "com.example.RegisterTest",
            TestResult.ResultType.SUCCESS, 100, 250, null
        )
        collector.collectTestResult(
            ":lib", "testParse", "com.example.ParserTest",
            TestResult.ResultType.FAILURE, 0, 50,
            AssertionError("expected 42 but was 0").apply {
                stackTrace = arrayOf(
                    StackTraceElement("org.junit.jupiter.api.Assertions", "assertEquals", "Assertions.java", 150),
                    StackTraceElement("com.example.ParserTest", "testParse", "ParserTest.kt", 28)
                )
            }
        )

        val report = collector.buildReport(
            totalDurationMs = 10000,
            isCi = true,
            scheme = "android-app",
            gitBranch = "main",
            gitCommitSha = "abc123",
            gitRef = "v2.0",
            gitRemoteUrlOrigin = null,
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
