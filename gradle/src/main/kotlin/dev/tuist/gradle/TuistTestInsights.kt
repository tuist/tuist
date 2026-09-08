package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import org.gradle.api.file.DirectoryProperty
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
    @SerializedName("git_remote_url_origin") val gitRemoteUrlOrigin: String?,
    @SerializedName("gradle_build_id") val gradleBuildId: String? = null,
    @SerializedName("shard_plan_id") val shardPlanId: String? = null,
    @SerializedName("shard_index") val shardIndex: Int? = null,
    @SerializedName("stress_new_tests") val stressNewTests: StressNewTestsReport? = null,
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
    val repetitions: List<TestCaseRepetition>? = null,
    @SerializedName("is_quarantined") val isQuarantined: Boolean = false
)

data class TestCaseRepetition(
    @SerializedName("repetition_number") val repetitionNumber: Int,
    val name: String,
    val status: String,
    val duration: Long,
    val source: String = "run"
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
    val exception: Throwable?,
    val isQuarantined: Boolean = false
)

internal class TestReportCollector {
    private val attemptsByModule = mutableMapOf<String, MutableList<TestAttempt>>()

    fun hasNonQuarantinedFailures(moduleName: String): Boolean {
        val attempts = attemptsByModule[moduleName] ?: return false
        return attempts.any { it.resultType == TestResult.ResultType.FAILURE && !it.isQuarantined }
    }

    fun hasQuarantinedFailures(moduleName: String): Boolean {
        val attempts = attemptsByModule[moduleName] ?: return false
        return attempts.any { it.resultType == TestResult.ResultType.FAILURE && it.isQuarantined }
    }

    fun collectTestResult(
        moduleName: String,
        testName: String,
        className: String?,
        resultType: TestResult.ResultType,
        startTime: Long,
        endTime: Long,
        exception: Throwable?,
        isQuarantined: Boolean = false
    ) {
        attemptsByModule.getOrPut(moduleName) { mutableListOf() }.add(
            TestAttempt(testName, className, resultType, startTime, endTime, exception, isQuarantined)
        )
    }

    /**
     * One entry per test case, with the last attempt's result and the summed duration,
     * which is what the stress gate prices repetitions from.
     */
    fun executedTestCases(): List<ExecutedTestCase> {
        return attemptsByModule.flatMap { (moduleName, attempts) ->
            attempts
                .groupBy { Pair(it.testName, it.className) }
                .map { (key, caseAttempts) ->
                    val last = caseAttempts.last()
                    ExecutedTestCase(
                        moduleName = moduleName,
                        className = key.second,
                        testName = key.first,
                        durationMs = caseAttempts.sumOf { it.endTime - it.startTime },
                        resultType = last.resultType,
                        isQuarantined = caseAttempts.any { it.isQuarantined }
                    )
                }
        }
    }

    fun repetitionResults(): List<StressRepetitionResult> {
        return attemptsByModule.flatMap { (moduleName, attempts) ->
            attempts.map {
                StressRepetitionResult(
                    moduleName = moduleName,
                    className = it.className,
                    testName = it.testName,
                    // A rerun that aborted through an assumption did not fail: it said nothing.
                    // Counting it as a failure would let a test block the build without a
                    // single assertion failing.
                    status = when (it.resultType) {
                        TestResult.ResultType.SUCCESS -> "success"
                        TestResult.ResultType.SKIPPED -> "skipped"
                        else -> "failure"
                    },
                    duration = it.endTime - it.startTime,
                    failureMessage = it.exception?.message
                )
            }
        }
    }

    fun buildReport(
        totalDurationMs: Long,
        isCi: Boolean,
        scheme: String?,
        gitBranch: String?,
        gitCommitSha: String?,
        gitRef: String?,
        gitRemoteUrlOrigin: String?,
        gradleBuildId: String?,
        shardPlanId: String? = null,
        shardIndex: Int? = null,
        stressNewTests: StressNewTestsReport? = null
    ): TestReport {
        val testModules = attemptsByModule.map { (moduleName, attempts) ->
            val testCases = buildTestCases(attempts).map { withStressReruns(it, moduleName, stressNewTests) }
            val moduleStatus = if (testCases.any { it.status == "failure" && !it.isQuarantined }) "failure" else "success"
            val moduleDuration = testCases.sumOf { it.duration }

            val testSuites = testCases
                .mapNotNull { case -> case.testSuiteName?.let { it to case } }
                .groupBy({ it.first }, { it.second })
                .map { (suiteName, cases) ->
                    TestSuite(
                        name = suiteName,
                        status = if (cases.any { it.status == "failure" && !it.isQuarantined }) "failure" else "success",
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

        val hasNonQuarantinedFailure = testModules.any { it.status == "failure" }
        val overallStatus = if (hasNonQuarantinedFailure) "failure" else "success"

        return TestReport(
            duration = totalDurationMs,
            status = overallStatus,
            isCi = isCi,
            scheme = scheme,
            buildSystem = "gradle",
            gitBranch = gitBranch,
            gitCommitSha = gitCommitSha,
            gitRef = gitRef,
            gitRemoteUrlOrigin = gitRemoteUrlOrigin,
            gradleBuildId = gradleBuildId,
            shardPlanId = shardPlanId,
            shardIndex = shardIndex,
            stressNewTests = stressNewTests,
            testModules = testModules
        )
    }

    // The gate's reruns are executions of the test case like its retries, so they are
    // reported with it, numbered after its own attempts and tagged so the dashboard can
    // say which were solicited. A rerun's failure is kept on the test case beside the
    // others, which is where the run page reads failures from.
    private fun withStressReruns(testCase: TestCase, moduleName: String, stress: StressNewTestsReport?): TestCase {
        val candidate = stress?.testCases?.firstOrNull {
            it.moduleName == moduleName &&
                it.name == testCase.name &&
                (it.suiteName?.takeIf { s -> s.isNotBlank() }) == testCase.testSuiteName
        } ?: return testCase
        if (candidate.repetitionResults.isEmpty()) return testCase

        val own = testCase.repetitions.orEmpty()
        val reruns = candidate.repetitionResults.mapIndexed { index, result ->
            TestCaseRepetition(
                repetitionNumber = own.size + index + 1,
                name = "Stress ${index + 1}",
                status = result.status,
                duration = result.duration,
                source = "stress"
            )
        }
        val failures = candidate.repetitionResults
            .filter { it.status == "failure" }
            .mapNotNull { it.failure }
            .map { TestFailure(message = it.message, path = null, lineNumber = 0, issueType = it.issueType) }

        return testCase.copy(repetitions = own + reruns, failures = testCase.failures + failures)
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
                    repetitions = repetitions,
                    isQuarantined = attempts.any { it.isQuarantined }
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
        val useEnvironmentProxy: Property<Boolean>
        val rootProjectName: Property<String>
        val projectDir: DirectoryProperty
        val gitBranch: Property<String>
        val gitCommitSha: Property<String>
        val gitRef: Property<String>
        val gitRemoteUrlOrigin: Property<String>
    }

    private val logger = Logging.getLogger(TuistTestInsightsService::class.java)

    internal var gitInfoProvider: GitInfoProvider? = null
    internal var ciDetector: CIDetector = EnvironmentCIDetector()
    internal var uploadInBackground: Boolean? = null
    internal var buildInsightsService: TuistBuildInsightsService? = null
    internal var shardPlanId: String? = null
    internal var shardIndex: Int? = null
    internal var stressNewTestsReport: StressNewTestsReport? = null

    /**
     * When set, this build is a stress repetition: the results are written here for the
     * parent build to read instead of being reported as a test run of their own.
     */
    internal var stressRepetitionOutput: java.io.File? = null

    private val testTaskPathsByModule = mutableMapOf<String, MutableSet<String>>()

    private val collector = TestReportCollector()
    private var earliestStartTime: Long = Long.MAX_VALUE
    private var latestEndTime: Long = Long.MIN_VALUE
    @Volatile private var hasTests = false

    @Volatile
    internal var quarantineMap: Map<String, List<TestIdentifier>> = emptyMap()

    internal fun hasNonQuarantinedFailures(moduleName: String): Boolean {
        return collector.hasNonQuarantinedFailures(moduleName)
    }

    internal fun hasQuarantinedFailures(moduleName: String): Boolean {
        return collector.hasQuarantinedFailures(moduleName)
    }

    @Synchronized
    internal fun registerTestTask(moduleName: String, taskPath: String) {
        testTaskPathsByModule.getOrPut(moduleName) { linkedSetOf() }.add(taskPath)
    }

    @Synchronized
    internal fun taskPathsByModule(): Map<String, List<String>> =
        testTaskPathsByModule.mapValues { it.value.toList() }

    @Synchronized
    internal fun executedTestCases(): List<ExecutedTestCase> = collector.executedTestCases()

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
        val quarantinedIds = quarantineMap[moduleName] ?: emptyList()
        val isQuarantined = quarantinedIds.any { it.matches(descriptor.className, descriptor.name) }
        collector.collectTestResult(
            moduleName, descriptor.name, descriptor.className,
            actualResultType, result.startTime, result.endTime, result.exception, isQuarantined
        )
    }

    override fun close() {
        stressRepetitionOutput?.let { output ->
            output.parentFile?.mkdirs()
            output.writer().use { Gson().toJson(StressRepetitionResults(collector.repetitionResults()), it) }
            return
        }

        if (!hasTests) {
            logger.debug("Tuist: No test results collected, skipping test insights upload.")
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
        val httpClients = TuistHttpClients(useEnvironmentProxy = parameters.useEnvironmentProxy.get())
        val projectDir = parameters.projectDir.asFile.get()

        val configProvider = DefaultConfigurationProvider(
            project = projectValue,
            serverUrl = parameters.url.get(),
            projectDir = projectDir,
            httpClients = httpClients
        )

        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            httpClients = httpClients,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 10_000
        )

        val totalDurationMs = latestEndTime - earliestStartTime
        val gradleBuildId = buildInsightsService?.buildId
        val reportGitInfoProvider = reportGitInfoProvider()

        val report = collector.buildReport(
            totalDurationMs = totalDurationMs,
            isCi = ciDetector.isCi(),
            scheme = parameters.rootProjectName.orNull,
            gitBranch = reportGitInfoProvider.branch(),
            gitCommitSha = reportGitInfoProvider.commitSha(),
            gitRef = reportGitInfoProvider.ref(),
            gitRemoteUrlOrigin = reportGitInfoProvider.remoteUrlOrigin(),
            gradleBuildId = gradleBuildId,
            shardPlanId = shardPlanId,
            shardIndex = shardIndex,
            stressNewTests = stressNewTestsReport
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

    private fun reportGitInfoProvider(): GitInfoProvider =
        gitInfoProvider ?: GitInfo(
            branch = parameters.gitBranch.orNull,
            commitSha = parameters.gitCommitSha.orNull,
            ref = parameters.gitRef.orNull,
            remoteUrlOrigin = parameters.gitRemoteUrlOrigin.orNull
        )
}

// --- Plugin ---

internal abstract class TuistTestInsightsPlugin @Inject constructor() : Plugin<Project> {

    private val logger = Logging.getLogger(TuistTestInsightsPlugin::class.java)

    internal var ciDetector: CIDetector = EnvironmentCIDetector()

    override fun apply(project: Project) {
        if (project !== project.rootProject) return

        val config = TuistGradleConfig.from(project) ?: return
        val gitInfo = project.providers.of(GitInfoValueSource::class.java) {}.get()

        val serviceProvider = project.gradle.sharedServices.registerIfAbsent(
            "tuistTestInsights",
            TuistTestInsightsService::class.java
        ) {
            parameters.url.set(config.url)
            config.project?.let { parameters.project.set(it) }
            parameters.useEnvironmentProxy.set(config.network.proxy)
            parameters.rootProjectName.set(project.rootProject.name)
            parameters.projectDir.set(project.rootProject.layout.projectDirectory)
            parameters.gitBranch.set(gitInfo.branch())
            parameters.gitCommitSha.set(gitInfo.commitSha())
            parameters.gitRef.set(gitInfo.ref())
            parameters.gitRemoteUrlOrigin.set(gitInfo.remoteUrlOrigin())
        }

        val repetition = config.stressRepetition
        val quarantineEnabled = repetition == null && (config.testQuarantineEnabled ?: ciDetector.isCi())

        val stressTaskProvider = config.stressNewTestsMode?.takeIf { repetition == null }?.let { mode ->
            project.tasks.register("tuistStressNewTests", TuistStressNewTestsTask::class.java) {
                group = "verification"
                description = "Reruns the test cases this build added and flags any that prove flaky."
                this.mode.set(mode)
                serverUrl.set(config.url)
                config.project?.let { tuistProject.set(it) }
                useEnvironmentProxy.set(config.network.proxy)
                projectDir.set(project.rootProject.layout.projectDirectory)
                gradleUserHomeDir.set(project.gradle.gradleUserHomeDir)
                project.gradle.gradleHomeDir?.let { gradleHomeDir.set(it) }
                insightsService.set(serviceProvider)
                usesService(serviceProvider)
            }
        }
        val quarantineServiceProvider = if (quarantineEnabled) {
            project.gradle.sharedServices.registerIfAbsent(
                "tuistTestQuarantine",
                TuistTestQuarantineBuildService::class.java
            ) {
                parameters.serverUrl.set(config.url)
                config.project?.let { parameters.tuistProject.set(it) }
                parameters.useEnvironmentProxy.set(config.network.proxy)
                parameters.projectDir.set(project.rootProject.layout.projectDirectory)
            }
        } else {
            null
        }

        // Declared once, on the stress task, against the live collection of test tasks.
        // Configuring the stress task through its provider from inside a test task's own
        // configuration is refused once the task graph is being resolved, which is exactly
        // when `gradle test` realizes that test task.
        stressTaskProvider?.configure {
            mustRunAfter(project.allprojects.map { it.tasks.withType(Test::class.java) })
        }

        project.allprojects {
            val subproject = this
            subproject.tasks.withType(Test::class.java).configureEach {
                val testTask = this
                testTask.usesService(serviceProvider)
                val moduleName = if (subproject.path == ":") subproject.name else subproject.path
                testTask.addTestListener(object : TestListener {
                    override fun beforeSuite(suite: TestDescriptor) {}
                    override fun afterSuite(suite: TestDescriptor, result: TestResult) {}
                    override fun beforeTest(testDescriptor: TestDescriptor) {}
                    override fun afterTest(testDescriptor: TestDescriptor, result: TestResult) {
                        serviceProvider.get().onTestFinished(moduleName, testDescriptor, result)
                    }
                })

                val taskPath = testTask.path
                testTask.doFirst {
                    serviceProvider.get().registerTestTask(moduleName, taskPath)
                }

                if (repetition != null) {
                    // A repetition reruns exactly the patterns it was handed, whatever Gradle's
                    // up-to-date check says, and lets the parent build decide what a failure means.
                    val patterns = repetition.filtersByTaskPath[taskPath].orEmpty()
                    testTask.outputs.upToDateWhen { false }
                    testTask.ignoreFailures = true
                    testTask.doFirst {
                        testTask.filter.isFailOnNoMatchingTests = false
                        patterns.forEach { testTask.filter.includeTestsMatching(it) }
                        serviceProvider.get().stressRepetitionOutput = repetition.outputFile
                    }
                }

                stressTaskProvider?.let { stressTask ->
                    testTask.finalizedBy(stressTask)
                }

                if (quarantineServiceProvider != null) {
                    testTask.usesService(quarantineServiceProvider)
                    testTask.ignoreFailures = true

                    testTask.doFirst {
                        val quarantinedTests = quarantineServiceProvider.get().getQuarantinedTests()
                        // The post-run failure mask only needs muted tests:
                        // skipped ones don't run, so they can't produce
                        // failures we need to mask.
                        serviceProvider.get().quarantineMap = quarantinedTests.muted

                        val mutedInModule = quarantinedTests.muted[moduleName] ?: emptyList()
                        val skippedInModule = quarantinedTests.skipped[moduleName] ?: emptyList()

                        // Exclude skipped tests via Gradle's TestFilter so
                        // they never run. Patterns use ANT-style globs:
                        // "ClassName.methodName" or "*.methodName" if we
                        // don't have a suite.
                        skippedInModule.forEach { id ->
                            val pattern = if (id.suiteName != null) {
                                "${id.suiteName}.${id.testName}"
                            } else {
                                "*.${id.testName}"
                            }
                            testTask.filter.excludeTestsMatching(pattern)
                        }

                        if (mutedInModule.isNotEmpty() || skippedInModule.isNotEmpty()) {
                            logger.lifecycle(
                                "Tuist: Found ${mutedInModule.size + skippedInModule.size} quarantined test(s) " +
                                    "in module $moduleName (${mutedInModule.size} muted, ${skippedInModule.size} skipped)"
                            )
                        }
                    }

                    testTask.doLast {
                        val service = serviceProvider.get()
                        if (service.hasNonQuarantinedFailures(moduleName)) {
                            throw org.gradle.api.GradleException("There were failing tests in module $moduleName")
                        } else if (service.hasQuarantinedFailures(moduleName)) {
                            logger.lifecycle("Tuist: All failing tests in module $moduleName are quarantined")
                        }
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
