package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.logging.Logging
import org.gradle.api.provider.Property
import org.gradle.api.services.BuildService
import org.gradle.api.services.BuildServiceParameters
import org.gradle.api.tasks.testing.Test
import org.gradle.api.tasks.testing.TestDescriptor
import org.gradle.api.tasks.testing.TestListener
import org.gradle.api.tasks.testing.TestResult
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import javax.inject.Inject

// --- Data classes ---

data class TestReport(
    val duration: Long,
    val status: String,
    @SerializedName("is_ci") val isCi: Boolean,
    val scheme: String?,
    @SerializedName("build_system") val buildSystem: String = "gradle",
    @SerializedName("git_branch") val gitBranch: String?,
    @SerializedName("git_commit_sha") val gitCommitSha: String?,
    @SerializedName("git_ref") val gitRef: String?,
    @SerializedName("gradle_build_id") val gradleBuildId: String? = null,
    @SerializedName("test_modules") val testModules: List<TestModule>
)

data class TestModule(
    val name: String,
    val status: String,
    val duration: Long,
    @SerializedName("test_suites") val testSuites: List<TestSuite>,
    @SerializedName("test_cases") val testCases: List<TestCase>
)

data class TestSuite(
    val name: String,
    val status: String,
    val duration: Long
)

data class TestCase(
    val name: String,
    @SerializedName("test_suite_name") val testSuiteName: String?,
    val status: String,
    val duration: Long,
    val failures: List<TestFailure>,
    val repetitions: List<TestCaseRepetition>? = null
)

data class TestCaseRepetition(
    @SerializedName("repetition_number") val repetitionNumber: Int,
    val name: String,
    val status: String,
    val duration: Long
)

data class TestFailure(
    val message: String?,
    val path: String?,
    @SerializedName("line_number") val lineNumber: Int,
    @SerializedName("issue_type") val issueType: String
)

data class TestResponse(val id: String, val url: String?)

// --- Test report collector ---

internal data class TestAttempt(
    val testName: String,
    val className: String?,
    val resultType: TestResult.ResultType,
    val startTime: Long,
    val endTime: Long,
    val exception: Throwable?
)

internal class TestReportCollector {
    private val attemptsByModule = mutableMapOf<String, MutableList<TestAttempt>>()

    fun collectTestResult(
        moduleName: String,
        testName: String,
        className: String?,
        resultType: TestResult.ResultType,
        startTime: Long,
        endTime: Long,
        exception: Throwable?
    ) {
        attemptsByModule.getOrPut(moduleName) { mutableListOf() }.add(
            TestAttempt(testName, className, resultType, startTime, endTime, exception)
        )
    }

    fun buildReport(
        totalDurationMs: Long,
        isCi: Boolean,
        scheme: String?,
        gitBranch: String?,
        gitCommitSha: String?,
        gitRef: String?,
        gradleBuildId: String?
    ): TestReport {
        val testModules = attemptsByModule.map { (moduleName, attempts) ->
            val testCases = buildTestCases(attempts)
            val moduleStatus = if (testCases.any { it.status == "failure" }) "failure" else "success"
            val moduleDuration = testCases.sumOf { it.duration }

            val testSuites = testCases
                .mapNotNull { case -> case.testSuiteName?.let { it to case } }
                .groupBy({ it.first }, { it.second })
                .map { (suiteName, cases) ->
                    TestSuite(
                        name = suiteName,
                        status = if (cases.any { it.status == "failure" }) "failure" else "success",
                        duration = cases.sumOf { it.duration }
                    )
                }

            TestModule(
                name = moduleName,
                status = moduleStatus,
                duration = moduleDuration,
                testSuites = testSuites,
                testCases = testCases
            )
        }

        val hasFailure = testModules.any { it.status == "failure" }
        val overallStatus = if (hasFailure) "failure" else "success"

        return TestReport(
            duration = totalDurationMs,
            status = overallStatus,
            isCi = isCi,
            scheme = scheme,
            buildSystem = "gradle",
            gitBranch = gitBranch,
            gitCommitSha = gitCommitSha,
            gitRef = gitRef,
            gradleBuildId = gradleBuildId,
            testModules = testModules
        )
    }

    private fun buildTestCases(attempts: List<TestAttempt>): List<TestCase> {
        return attempts
            .groupBy { Pair(it.testName, it.className) }
            .map { (key, attempts) ->
                val (testName, className) = key
                val lastAttempt = attempts.last()
                val finalStatus = mapTestResultType(lastAttempt.resultType)
                val totalDuration = attempts.sumOf { it.endTime - it.startTime }

                val repetitions = if (attempts.size > 1) {
                    attempts.mapIndexed { index, attempt ->
                        // Repetitions only support "success" or "failure" —
                        // the test-retry plugin may report SKIPPED for retried
                        // attempts, so treat anything non-success as failure.
                        val status = if (attempt.resultType == TestResult.ResultType.SUCCESS) "success" else "failure"
                        TestCaseRepetition(
                            repetitionNumber = index + 1,
                            name = if (index == 0) "Run 1" else "Retry $index",
                            status = status,
                            duration = attempt.endTime - attempt.startTime
                        )
                    }
                } else {
                    null
                }

                val failures = if (repetitions != null) {
                    attempts.flatMap { attempt -> mapTestFailures(attempt.resultType, attempt.exception) }
                } else {
                    mapTestFailures(lastAttempt.resultType, lastAttempt.exception)
                }

                TestCase(
                    name = testName,
                    testSuiteName = className,
                    status = finalStatus,
                    duration = totalDuration,
                    failures = failures,
                    repetitions = repetitions
                )
            }
    }

    private fun mapTestResultType(resultType: TestResult.ResultType): String {
        return when (resultType) {
            TestResult.ResultType.SUCCESS -> "success"
            TestResult.ResultType.FAILURE -> "failure"
            TestResult.ResultType.SKIPPED -> "skipped"
        }
    }

    private fun isFrameworkFrame(frame: StackTraceElement): Boolean {
        val className = frame.className
        return className.startsWith("org.junit.") ||
            className.startsWith("junit.") ||
            className.startsWith("org.gradle.") ||
            className.startsWith("java.lang.reflect.") ||
            className.startsWith("sun.reflect.") ||
            className.startsWith("jdk.internal.reflect.") ||
            className.startsWith("org.opentest4j.")
    }

    private fun mapTestFailures(
        resultType: TestResult.ResultType,
        exception: Throwable?
    ): List<TestFailure> {
        if (resultType != TestResult.ResultType.FAILURE) return emptyList()

        if (exception == null) return listOf(
            TestFailure(
                message = "Test failed",
                path = null,
                lineNumber = 0,
                issueType = "error_thrown"
            )
        )

        val issueType = if (exception is AssertionError ||
            exception.javaClass.name.contains("AssertionError") ||
            exception.javaClass.name.contains("AssertError") ||
            exception.javaClass.name.contains("ComparisonFailure") ||
            exception is java.lang.AssertionError
        ) {
            "assertion_failure"
        } else {
            "error_thrown"
        }

        val stackTrace = exception.stackTrace ?: emptyArray()
        val userFrame = stackTrace.firstOrNull { frame ->
            !isFrameworkFrame(frame)
        }

        return listOf(
            TestFailure(
                message = exception.message,
                path = userFrame?.fileName,
                lineNumber = userFrame?.lineNumber ?: 0,
                issueType = issueType
            )
        )
    }
}

// --- Build Service ---

abstract class TuistTestInsightsService :
    BuildService<TuistTestInsightsService.Params>,
    AutoCloseable {

    interface Params : BuildServiceParameters {
        val url: Property<String>
        val project: Property<String>
        val executablePath: Property<String>
        val rootProjectName: Property<String>
    }

    private val logger = Logging.getLogger(TuistTestInsightsService::class.java)

    internal var gitInfoProvider: GitInfoProvider = ProcessGitInfoProvider()
    internal var ciDetector: CIDetector = EnvironmentCIDetector()
    internal var uploadInBackground: Boolean? = null
    internal var buildInsightsService: TuistBuildInsightsService? = null

    private val collector = TestReportCollector()
    private var earliestStartTime: Long = Long.MAX_VALUE
    private var latestEndTime: Long = Long.MIN_VALUE
    @Volatile private var hasTests = false

    @Synchronized
    internal fun onTestFinished(
        moduleName: String,
        descriptor: TestDescriptor,
        result: TestResult
    ) {
        hasTests = true
        if (result.startTime < earliestStartTime) earliestStartTime = result.startTime
        if (result.endTime > latestEndTime) latestEndTime = result.endTime
        // The test-retry plugin (org.gradle.test-retry) has a known bug where
        // afterTest reports resultType as SKIPPED instead of the actual result
        // when a test is being retried. Use the counts as a workaround.
        val actualResultType = when {
            result.failedTestCount > 0 -> TestResult.ResultType.FAILURE
            result.successfulTestCount > 0 -> TestResult.ResultType.SUCCESS
            else -> result.resultType
        }
        collector.collectTestResult(
            moduleName, descriptor.name, descriptor.className,
            actualResultType, result.startTime, result.endTime, result.exception
        )
    }

    override fun close() {
        if (!hasTests) {
            logger.lifecycle("Tuist: No test results collected, skipping test insights upload.")
            return
        }

        val shouldUploadInBackground = uploadInBackground ?: !ciDetector.isCi()

        if (shouldUploadInBackground) {
            logger.lifecycle("Tuist: Uploading test insights in the background...")
            Thread({
                try {
                    sendReport()
                } catch (e: Exception) {
                    logger.warn("Tuist: Failed to send test insights: ${e.message}")
                }
            }, "tuist-test-insights-upload").apply {
                isDaemon = false
                start()
            }
        } else {
            try {
                sendReport()
            } catch (e: Exception) {
                logger.warn("Tuist: Failed to send test insights: ${e.message}")
            }
        }
    }

    private fun sendReport() {
        val projectValue = parameters.project.orNull

        val configProvider = TuistCommandConfigurationProvider(
            project = projectValue,
            command = listOf(parameters.executablePath.orNull ?: "tuist"),
            url = parameters.url.get(),
            projectDir = java.io.File(System.getProperty("user.dir"))
        )

        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )

        val totalDurationMs = latestEndTime - earliestStartTime
        val gradleBuildId = buildInsightsService?.buildId

        val report = collector.buildReport(
            totalDurationMs = totalDurationMs,
            isCi = ciDetector.isCi(),
            scheme = parameters.rootProjectName.orNull,
            gitBranch = gitInfoProvider.branch(),
            gitCommitSha = gitInfoProvider.commitSha(),
            gitRef = gitInfoProvider.ref(),
            gradleBuildId = gradleBuildId
        )

        val response = httpClient.execute { config ->
            val baseUrl = parameters.url.get().trimEnd('/')
            val url = URI(baseUrl).resolve("/api/projects/${config.accountHandle}/${config.projectHandle}/tests")
            val connection = httpClient.openConnection(url, config)
            try {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")

                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    Gson().toJson(report, writer)
                }

                when (connection.responseCode) {
                    HttpURLConnection.HTTP_OK -> {
                        BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                            Gson().fromJson(reader, TestResponse::class.java)
                        }
                    }
                    HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                    else -> {
                        val errorBody = try {
                            connection.errorStream?.bufferedReader()?.use { it.readText() }
                        } catch (_: Exception) { null }
                        logger.warn("Tuist: Test insights request failed with HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}")
                        null
                    }
                }
            } finally {
                connection.disconnect()
            }
        }

        if (response != null) {
            logger.lifecycle("Tuist: Test insights reported successfully (test run ${response.id})")
        } else {
            logger.warn("Tuist: Failed to report test insights.")
        }
    }
}

// --- Plugin ---

internal abstract class TuistTestInsightsPlugin @Inject constructor() : Plugin<Project> {

    private val logger = Logging.getLogger(TuistTestInsightsPlugin::class.java)

    internal var ciDetector: CIDetector = EnvironmentCIDetector()

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistTestInsights",
            TuistTestInsightsService::class.java
        ) {
            parameters.url.set(config.url)
            config.project?.let { parameters.project.set(it) }
            parameters.executablePath.set(config.executablePath)
            parameters.rootProjectName.set(project.rootProject.name)
        }

        val quarantineEnabled = config.testQuarantineEnabled ?: ciDetector.isCi()
        val quarantineService = if (quarantineEnabled) {
            val configProvider = TuistCommandConfigurationProvider(
                project = config.project,
                command = listOf(config.executablePath),
                url = config.url,
                projectDir = java.io.File(System.getProperty("user.dir"))
            )
            val httpClient = TuistHttpClient(
                configurationProvider = configProvider,
                connectTimeoutMs = 10_000,
                readTimeoutMs = 10_000
            )
            TuistTestQuarantineService(httpClient = httpClient, baseUrl = config.url)
        } else {
            null
        }

        project.allprojects {
            val subproject = this
            subproject.tasks.withType(Test::class.java).configureEach {
                val testTask = this
                testTask.usesService(serviceProvider)
                val moduleName = subproject.path
                testTask.addTestListener(object : TestListener {
                    override fun beforeSuite(suite: TestDescriptor) {}
                    override fun afterSuite(suite: TestDescriptor, result: TestResult) {}
                    override fun beforeTest(testDescriptor: TestDescriptor) {}
                    override fun afterTest(testDescriptor: TestDescriptor, result: TestResult) {
                        serviceProvider.get().onTestFinished(moduleName, testDescriptor, result)
                    }
                })

                if (quarantineService != null) {
                    testTask.doFirst {
                        val exclusions = quarantineService.getQuarantinedTests()
                        val moduleExclusions = exclusions[moduleName] ?: return@doFirst
                        for (pattern in moduleExclusions) {
                            testTask.filter.excludeTestsMatching(pattern)
                        }
                        logger.lifecycle("Tuist: Quarantined ${moduleExclusions.size} test(s) in module $moduleName")
                    }
                }
            }
        }

        project.gradle.taskGraph.whenReady {
            val service = serviceProvider.get()
            service.uploadInBackground = config.uploadInBackground

            val buildService = project.gradle.sharedServices.registrations
                .findByName("tuistBuildInsights")?.service?.orNull as? TuistBuildInsightsService
            if (buildService != null) {
                service.buildInsightsService = buildService
            }
        }

    }
}
