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

data class TestReportRequest(
    val duration: Long,
    val status: String,
    @SerializedName("is_ci") val isCi: Boolean,
    val scheme: String?,
    @SerializedName("build_system") val buildSystem: String = "gradle",
    @SerializedName("macos_version") val macosVersion: String = "",
    @SerializedName("xcode_version") val xcodeVersion: String = "",
    @SerializedName("model_identifier") val modelIdentifier: String = "",
    @SerializedName("git_branch") val gitBranch: String?,
    @SerializedName("git_commit_sha") val gitCommitSha: String?,
    @SerializedName("git_ref") val gitRef: String?,
    @SerializedName("gradle_build_id") val gradleBuildId: String? = null,
    @SerializedName("test_modules") val testModules: List<TestModuleReport>
)

data class TestModuleReport(
    val name: String,
    val status: String,
    val duration: Long,
    @SerializedName("test_suites") val testSuites: List<TestSuiteReport>,
    @SerializedName("test_cases") val testCases: List<TestCaseReport>
)

data class TestSuiteReport(
    val name: String,
    val status: String,
    val duration: Long
)

data class TestCaseReport(
    val name: String,
    @SerializedName("test_suite_name") val testSuiteName: String?,
    val status: String,
    val duration: Long,
    val failures: List<TestFailureReport>
)

data class TestFailureReport(
    val message: String?,
    val path: String?,
    @SerializedName("line_number") val lineNumber: Int,
    @SerializedName("issue_type") val issueType: String
)

data class TestReportResponse(val id: String, val url: String?)

// --- Internal data for collection ---

internal data class CollectedTestCase(
    val name: String,
    val suiteName: String?,
    val status: String,
    val durationMs: Long,
    val failures: List<TestFailureReport>
)

internal data class CollectedTestSuite(
    val name: String,
    var status: String = "success",
    var durationMs: Long = 0
)

internal data class CollectedTestModule(
    val name: String,
    var status: String = "success",
    var durationMs: Long = 0,
    val suites: MutableMap<String, CollectedTestSuite> = mutableMapOf(),
    val testCases: MutableList<CollectedTestCase> = mutableListOf()
)

// --- Standalone testable functions ---

internal fun mapTestResultType(resultType: TestResult.ResultType): String {
    return when (resultType) {
        TestResult.ResultType.SUCCESS -> "success"
        TestResult.ResultType.FAILURE -> "failure"
        TestResult.ResultType.SKIPPED -> "skipped"
        else -> "failure"
    }
}

internal fun isFrameworkFrame(frame: StackTraceElement): Boolean {
    val className = frame.className
    return className.startsWith("org.junit.") ||
        className.startsWith("junit.") ||
        className.startsWith("org.gradle.") ||
        className.startsWith("java.lang.reflect.") ||
        className.startsWith("sun.reflect.") ||
        className.startsWith("jdk.internal.reflect.") ||
        className.startsWith("org.opentest4j.")
}

internal fun mapTestFailures(
    resultType: TestResult.ResultType,
    exception: Throwable?
): List<TestFailureReport> {
    if (resultType != TestResult.ResultType.FAILURE) return emptyList()

    if (exception == null) return listOf(
        TestFailureReport(
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
        TestFailureReport(
            message = exception.message,
            path = userFrame?.fileName,
            lineNumber = userFrame?.lineNumber ?: 0,
            issueType = issueType
        )
    )
}

internal fun collectTestResult(
    modules: MutableMap<String, CollectedTestModule>,
    moduleName: String,
    testName: String,
    className: String?,
    resultType: TestResult.ResultType,
    startTime: Long,
    endTime: Long,
    exception: Throwable?
) {
    val module = modules.getOrPut(moduleName) { CollectedTestModule(name = moduleName) }
    val durationMs = endTime - startTime

    if (className != null) {
        val suite = module.suites.getOrPut(className) { CollectedTestSuite(name = className) }
        suite.durationMs += durationMs
        if (resultType == TestResult.ResultType.FAILURE) {
            suite.status = "failure"
        }
    }

    val status = mapTestResultType(resultType)
    val failures = mapTestFailures(resultType, exception)

    module.testCases.add(
        CollectedTestCase(
            name = testName,
            suiteName = className,
            status = status,
            durationMs = durationMs,
            failures = failures
        )
    )

    if (resultType == TestResult.ResultType.FAILURE) {
        module.status = "failure"
    }
    module.durationMs += durationMs
}

internal fun buildTestReportFromModules(
    modules: Map<String, CollectedTestModule>,
    totalDurationMs: Long,
    isCi: Boolean,
    scheme: String?,
    gitBranch: String?,
    gitCommitSha: String?,
    gitRef: String?,
    gradleBuildId: String?
): TestReportRequest {
    val hasFailure = modules.values.any { it.status == "failure" }
    val overallStatus = if (hasFailure) "failure" else "success"

    val testModules = modules.values.map { module ->
        TestModuleReport(
            name = module.name,
            status = module.status,
            duration = module.durationMs,
            testSuites = module.suites.values.map { suite ->
                TestSuiteReport(
                    name = suite.name,
                    status = suite.status,
                    duration = suite.durationMs
                )
            },
            testCases = module.testCases.map { tc ->
                TestCaseReport(
                    name = tc.name,
                    testSuiteName = tc.suiteName,
                    status = tc.status,
                    duration = tc.durationMs,
                    failures = tc.failures
                )
            }
        )
    }

    return TestReportRequest(
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

    private val modules = mutableMapOf<String, CollectedTestModule>()
    private var buildStartTime: Long = System.currentTimeMillis()
    @Volatile private var hasTests = false

    @Synchronized
    internal fun onTestFinished(
        moduleName: String,
        descriptor: TestDescriptor,
        result: TestResult
    ) {
        hasTests = true
        collectTestResult(
            modules, moduleName, descriptor.name, descriptor.className,
            result.resultType, result.startTime, result.endTime, result.exception
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

    internal fun buildTestReport(): TestReportRequest {
        val totalDurationMs = System.currentTimeMillis() - buildStartTime
        val gradleBuildId = buildInsightsService?.awaitBuildId()

        return buildTestReportFromModules(
            modules = modules,
            totalDurationMs = totalDurationMs,
            isCi = ciDetector.isCi(),
            scheme = parameters.rootProjectName.orNull,
            gitBranch = gitInfoProvider.branch(),
            gitCommitSha = gitInfoProvider.commitSha(),
            gitRef = gitInfoProvider.ref(),
            gradleBuildId = gradleBuildId
        )
    }

    private fun sendReport() {
        val projectValue = parameters.project.get()
        val parts = projectValue.split("/")
        if (parts.size != 2) {
            logger.warn("Tuist: Invalid project format for test insights: $projectValue")
            return
        }
        val (accountHandle, projectHandle) = parts

        val configProvider = TuistCommandConfigurationProvider(
            project = projectValue,
            command = listOf(parameters.executablePath.orNull ?: "tuist"),
            url = parameters.url.get()
        )

        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )

        val report = buildTestReport()

        val baseUrl = parameters.url.get().trimEnd('/')

        val response = httpClient.execute { config ->
            val url = URI(baseUrl).resolve("/api/projects/$accountHandle/$projectHandle/tests")
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
                            Gson().fromJson(reader, TestReportResponse::class.java)
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
    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistTestInsights",
            TuistTestInsightsService::class.java
        ) {
            parameters.url.set(config.url)
            parameters.project.set(config.project)
            parameters.executablePath.set(config.executablePath)
            parameters.rootProjectName.set(project.rootProject.name)
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
