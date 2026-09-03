package dev.tuist.gradle

import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.logging.Logger
import org.gradle.api.logging.Logging
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.TaskAction
import org.gradle.api.tasks.testing.TestResult
import org.gradle.tooling.GradleConnector
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI

// --- Modes and nested-build context ---

internal object StressNewTestsMode {
    const val REPORT = "report"
    const val ENFORCE = "enforce"

    private val logger = Logging.getLogger(StressNewTestsMode::class.java)

    fun resolve(environmentValue: String?, extensionValue: String?): String? {
        val value = environmentValue?.takeIf { it.isNotBlank() } ?: extensionValue?.takeIf { it.isNotBlank() } ?: return null
        return when (value) {
            REPORT, ENFORCE -> value
            else -> {
                logger.warn("Tuist: Ignoring unknown stressNewTests mode '$value'. Expected 'report' or 'enforce'.")
                null
            }
        }
    }
}

/**
 * What a stress repetition, a nested build launched by [TuistStressNewTestsTask],
 * was asked to do: rerun the given filters on the given test tasks and write the
 * per-test results to [outputFile].
 */
data class StressRepetitionContext(
    val filtersByTaskPath: Map<String, List<String>>,
    val outputFile: File
) {
    companion object {
        fun from(properties: Map<String, String>): StressRepetitionContext? {
            val filters = properties[TuistGradleConfig.STRESS_FILTERS_PROPERTY] ?: return null
            val output = properties[TuistGradleConfig.STRESS_OUTPUT_PROPERTY] ?: return null
            val type = object : TypeToken<Map<String, List<String>>>() {}.type
            return StressRepetitionContext(
                filtersByTaskPath = Gson().fromJson(filters, type),
                outputFile = File(output)
            )
        }
    }
}

// --- Verdict API models ---

data class StressVerdictRequest(@SerializedName("test_cases") val testCases: List<StressVerdictTestCase>)

data class StressVerdictTestCase(
    val name: String,
    @SerializedName("suite_name") val suiteName: String?,
    @SerializedName("module_name") val moduleName: String,
    val duration: Long?
)

data class StressVerdictResponse(
    val enabled: Boolean,
    val guard: StressGuard?,
    @SerializedName("inventory_count") val inventoryCount: Int,
    val candidates: List<StressVerdictCandidate>,
    val parameters: StressParameters
)

data class StressGuard(
    val kind: String,
    @SerializedName("new_count") val newCount: Int,
    @SerializedName("inventory_count") val inventoryCount: Int
)

data class StressVerdictCandidate(
    val name: String,
    @SerializedName("suite_name") val suiteName: String,
    @SerializedName("module_name") val moduleName: String,
    val repetitions: Int,
    @SerializedName("excluded_reason") val excludedReason: String?
)

data class StressParameters(
    @SerializedName("candidate_cap") val candidateCap: Int,
    @SerializedName("wall_clock_ceiling_ms") val wallClockCeilingMs: Long
)

// --- Report models, sent with the test run ---

data class StressNewTestsReport(
    val mode: String,
    val outcome: String,
    @SerializedName("skip_reason") val skipReason: String? = null,
    @SerializedName("new_count") val newCount: Int,
    @SerializedName("stressed_count") val stressedCount: Int,
    @SerializedName("excluded_count") val excludedCount: Int,
    @SerializedName("inventory_count") val inventoryCount: Int,
    @SerializedName("test_cases") val testCases: List<StressNewTestsCandidateReport>
) {
    val blockingCandidates: List<StressNewTestsCandidateReport>
        get() = testCases.filter { it.outcome == "disagreed" && !it.isQuarantined }

    val blocks: Boolean
        get() = mode == StressNewTestsMode.ENFORCE && blockingCandidates.isNotEmpty()
}

data class StressNewTestsCandidateReport(
    val name: String,
    @SerializedName("suite_name") val suiteName: String?,
    @SerializedName("module_name") val moduleName: String,
    val repetitions: Int,
    @SerializedName("failed_repetitions") val failedRepetitions: Int,
    val outcome: String,
    @SerializedName("is_quarantined") val isQuarantined: Boolean,
    @SerializedName("repetition_results") val repetitionResults: List<StressRepetitionReport> = emptyList()
) {
    val identifier: String
        get() = listOfNotNull(moduleName, suiteName?.takeIf { it.isNotBlank() }, name).joinToString("/")
}

// --- What a first pass executed, and what a repetition observed ---

internal data class ExecutedTestCase(
    val moduleName: String,
    val className: String?,
    val testName: String,
    val durationMs: Long,
    val resultType: TestResult.ResultType,
    val isQuarantined: Boolean
)

internal data class StressRepetitionResults(val results: List<StressRepetitionResult>)

internal data class StressRepetitionResult(
    @SerializedName("module_name") val moduleName: String,
    @SerializedName("class_name") val className: String?,
    @SerializedName("test_name") val testName: String,
    val status: String,
    val duration: Long = 0,
    @SerializedName("failure_message") val failureMessage: String? = null
)

/** One repetition as it is reported with the test run. */
data class StressRepetitionReport(
    @SerializedName("repetition_number") val repetitionNumber: Int,
    val status: String,
    val duration: Long,
    val failure: StressRepetitionFailure?
)

data class StressRepetitionFailure(
    val message: String?,
    @SerializedName("issue_type") val issueType: String
)

// --- Verdict client ---

class TuistStressNewTestsVerdictService(
    private val httpClient: TuistHttpClient,
    private val baseUrl: String
) {
    fun verdict(testCases: List<StressVerdictTestCase>): StressVerdictResponse {
        return httpClient.execute { config ->
            val url = URI(baseUrl.trimEnd('/')).resolve(
                "/api/projects/${config.accountHandle}/${config.projectHandle}/tests/stress-new-tests/verdict"
            )
            val connection = httpClient.openConnection(url, config)
            try {
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Accept", "application/json")
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { writer ->
                    Gson().toJson(StressVerdictRequest(testCases), writer)
                }
                when (connection.responseCode) {
                    HttpURLConnection.HTTP_OK ->
                        BufferedReader(InputStreamReader(connection.inputStream, Charsets.UTF_8)).use { reader ->
                            Gson().fromJson(reader, StressVerdictResponse::class.java)
                        }
                    HttpURLConnection.HTTP_UNAUTHORIZED -> throw TokenExpiredException()
                    else -> {
                        val errorBody = try {
                            connection.errorStream?.bufferedReader()?.use { it.readText() }
                        } catch (_: Exception) { null }
                        throw GradleException(
                            "HTTP ${connection.responseCode}: ${errorBody ?: "(no response body)"}"
                        )
                    }
                }
            } finally {
                connection.disconnect()
            }
        }
    }
}

// --- The gate, independent of Gradle so the loop can be tested ---

/**
 * Runs one repetition of the given filters and returns what it observed.
 * `filtersByTaskPath` maps a test task path to `Class.method` patterns.
 */
internal typealias StressRepetitionRunner =
    (filtersByTaskPath: Map<String, List<String>>, repetitions: Int, repetition: Int) -> List<StressRepetitionResult>

internal class StressNewTestsGate(
    private val mode: String,
    private val verdict: (List<StressVerdictTestCase>) -> StressVerdictResponse,
    private val runRepetition: StressRepetitionRunner,
    private val logger: Logger,
    private val nanoTime: () -> Long = System::nanoTime
) {
    private data class Candidate(
        val moduleName: String,
        val suiteName: String,
        val name: String,
        var repetitions: Int,
        var failedRepetitions: Int = 0,
        var outcome: String,
        val isQuarantined: Boolean,
        var repetitionResults: List<StressRepetitionReport> = emptyList()
    ) {
        val identifier: String
            get() = listOfNotNull(moduleName, suiteName.takeIf { it.isNotBlank() }, name).joinToString("/")

        val blocks: Boolean
            get() = outcome == "disagreed" && !isQuarantined

        fun toReport() = StressNewTestsCandidateReport(
            name = name,
            suiteName = suiteName.takeIf { it.isNotBlank() },
            moduleName = moduleName,
            repetitions = repetitions,
            failedRepetitions = failedRepetitions,
            outcome = outcome,
            isQuarantined = isQuarantined,
            repetitionResults = repetitionResults
        )
    }

    /**
     * Returns `null` when nothing ran and nothing should be recorded: the account is not entitled.
     */
    fun run(
        executed: List<ExecutedTestCase>,
        taskPathsByModule: Map<String, List<String>>
    ): StressNewTestsReport? {
        val firstPassFailed = executed.any { it.resultType == TestResult.ResultType.FAILURE && !it.isQuarantined }
        if (firstPassFailed) {
            heading()
            logger.lifecycle("  Skipped: the first pass already failed, so nothing was stressed.")
            return skipped("first_pass_failed", newCount = 0, inventoryCount = 0)
        }

        val ran = executed.filter { it.resultType != TestResult.ResultType.SKIPPED }
        val response = try {
            verdict(
                ran.map {
                    StressVerdictTestCase(
                        name = it.testName,
                        suiteName = it.className,
                        moduleName = it.moduleName,
                        duration = it.durationMs
                    )
                }
            )
        } catch (e: Exception) {
            logger.warn("Tuist: Failed to fetch the stress gate verdict: ${e.message}. Nothing was stressed.")
            return skipped("verdict_unavailable", newCount = 0, inventoryCount = 0)
        }

        if (!response.enabled) return null

        response.guard?.let { guard ->
            heading()
            logger.lifecycle("  " + guardDescription(guard))
            return skipped(guard.kind, newCount = guard.newCount, inventoryCount = guard.inventoryCount)
        }

        val quarantined = ran.filter { it.isQuarantined }
            .map { Triple(it.moduleName, it.className ?: "", it.testName) }
            .toSet()

        val candidates = response.candidates.map { candidate ->
            Candidate(
                moduleName = candidate.moduleName,
                suiteName = candidate.suiteName,
                name = candidate.name,
                repetitions = candidate.repetitions,
                outcome = when (candidate.excludedReason) {
                    "too_slow" -> "excluded_too_slow"
                    "candidate_cap" -> "excluded_candidate_cap"
                    else -> "passed"
                },
                isQuarantined = Triple(candidate.moduleName, candidate.suiteName, candidate.name) in quarantined
            )
        }

        if (candidates.isEmpty()) {
            return StressNewTestsReport(
                mode = mode,
                outcome = "no_candidates",
                newCount = 0,
                stressedCount = 0,
                excludedCount = 0,
                inventoryCount = response.inventoryCount,
                testCases = emptyList()
            )
        }

        val ceilingNanos = response.parameters.wallClockCeilingMs * 1_000_000
        val start = nanoTime()
        val groups = candidates.filter { it.repetitions > 0 }.groupBy { it.repetitions }

        for (repetitions in groups.keys.sortedDescending()) {
            val group = groups.getValue(repetitions)
            if (nanoTime() - start >= ceilingNanos) {
                group.forEach { it.outcome = "not_stressed_ceiling" }
                continue
            }

            val filtersByTaskPath = mutableMapOf<String, MutableList<String>>()
            for (candidate in group) {
                val pattern = filterPattern(candidate.suiteName, candidate.name)
                for (taskPath in taskPathsByModule[candidate.moduleName].orEmpty()) {
                    filtersByTaskPath.getOrPut(taskPath) { mutableListOf() }.add(pattern)
                }
            }
            if (filtersByTaskPath.isEmpty()) {
                group.forEach { it.outcome = "not_stressed_error" }
                continue
            }

            val observed = mutableMapOf<Triple<String, String, String>, MutableList<StressRepetitionResult>>()
            var failedToRun = false
            for (repetition in 1..repetitions) {
                if (nanoTime() - start >= ceilingNanos) break
                val results = try {
                    runRepetition(filtersByTaskPath, repetitions, repetition)
                } catch (e: Exception) {
                    logger.warn("Tuist: Stress repetition $repetition of $repetitions failed to run: ${e.message}")
                    failedToRun = true
                    break
                }
                for (result in results) {
                    observed.getOrPut(Triple(result.moduleName, result.className ?: "", result.testName)) { mutableListOf() }
                        .add(result)
                }
            }

            for (candidate in group) {
                val runs = observed[Triple(candidate.moduleName, candidate.suiteName, candidate.name)]
                if (runs != null) {
                    candidate.repetitionResults = runs.mapIndexed { index, run ->
                        StressRepetitionReport(
                            repetitionNumber = index + 1,
                            status = run.status,
                            duration = run.duration,
                            failure = run.failureMessage?.let {
                                StressRepetitionFailure(message = it, issueType = "assertion_failure")
                            }
                        )
                    }
                }
                when {
                    runs.isNullOrEmpty() && failedToRun -> candidate.outcome = "not_stressed_error"
                    runs.isNullOrEmpty() -> candidate.outcome = "not_stressed_ceiling"
                    runs.size < candidate.repetitions && !failedToRun && nanoTime() - start >= ceilingNanos -> {
                        candidate.repetitions = runs.size
                        candidate.failedRepetitions = runs.count { it.status == "failure" }
                        candidate.outcome = if (candidate.failedRepetitions > 0) "disagreed" else "not_stressed_ceiling"
                    }
                    else -> {
                        candidate.repetitions = maxOf(candidate.repetitions, runs.size)
                        candidate.failedRepetitions = runs.count { it.status == "failure" }
                        candidate.outcome = if (candidate.failedRepetitions > 0) "disagreed" else "passed"
                    }
                }
            }
        }

        val stressed = candidates.count { it.outcome == "passed" || it.outcome == "disagreed" }
        val report = StressNewTestsReport(
            mode = mode,
            outcome = if (candidates.any { it.blocks }) "disagreed" else "passed",
            newCount = candidates.size,
            stressedCount = stressed,
            excludedCount = candidates.size - stressed,
            inventoryCount = response.inventoryCount,
            testCases = candidates.map { it.toReport() }
        )
        print(report, response.parameters.wallClockCeilingMs)
        return report
    }

    private fun skipped(reason: String, newCount: Int, inventoryCount: Int) = StressNewTestsReport(
        mode = mode,
        outcome = "skipped",
        skipReason = reason,
        newCount = newCount,
        stressedCount = 0,
        excludedCount = 0,
        inventoryCount = inventoryCount,
        testCases = emptyList()
    )

    private fun heading() {
        logger.lifecycle("Tuist: Stress-testing new tests")
    }

    private fun print(report: StressNewTestsReport, ceilingMs: Long) {
        heading()
        logger.lifecycle("  ${report.newCount} new test cases, ${report.stressedCount} stressed, ${report.excludedCount} excluded")
        val width = report.testCases.maxOfOrNull { it.identifier.length } ?: 0
        for (candidate in report.testCases) {
            logger.lifecycle("  ${candidate.identifier.padEnd(width)}   ${outcomeDescription(candidate, ceilingMs)}")
        }
        if (report.mode == StressNewTestsMode.REPORT) {
            for (candidate in report.blockingCandidates) {
                logger.warn(
                    "Tuist: ${candidate.name} failed ${candidate.failedRepetitions} of ${candidate.repetitions} repetitions " +
                        "and would have blocked this build. Set stressNewTests { mode = \"enforce\" } to make it blocking."
                )
            }
        }
    }

    companion object {
        /**
         * Gradle matches `Class.method` against the method name without its parameter list,
         * so a JUnit 5 `test()` display name is trimmed to `test`.
         */
        fun filterPattern(suiteName: String, testName: String): String {
            val method = testName.substringBefore("(")
            return if (suiteName.isNotBlank()) "$suiteName.$method" else "*.$method"
        }

        fun outcomeDescription(candidate: StressNewTestsCandidateReport, ceilingMs: Long): String = when (candidate.outcome) {
            "passed" -> "${candidate.repetitions} repetitions, passed"
            "disagreed" -> "${candidate.repetitions} repetitions, ${candidate.failedRepetitions} failed" +
                if (candidate.isQuarantined) " (muted)" else ""
            "excluded_too_slow" -> "excluded, slower than the curve's last bucket"
            "excluded_candidate_cap" -> "excluded, beyond the candidate cap"
            "not_stressed_ceiling" -> {
                val seconds = ceilingMs / 1000
                val ceiling = if (seconds >= 60) "${seconds / 60} minute" else "$seconds second"
                "not stressed, the $ceiling wall-clock ceiling was reached"
            }
            else -> "not stressed, the stress pass failed to run"
        }

        fun guardDescription(guard: StressGuard): String = when (guard.kind) {
            "no_default_branch" ->
                "Skipped: the project has no default branch, so no test case can be new. Set one in the project settings."
            "no_default_branch_history" ->
                "Skipped: no test case has run in CI on the default branch yet, so all ${guard.newCount} test cases would read as new."
            else ->
                "Skipped: ${guard.newCount} of the build's test cases are new against ${guard.inventoryCount} on the default branch, " +
                    "so the bulk-change guard ran nothing."
        }

        fun blockedMessage(report: StressNewTestsReport): String =
            report.blockingCandidates.joinToString("\n") {
                "${it.name} failed ${it.failedRepetitions} of ${it.repetitions} repetitions and blocked this build."
            }
    }
}

// --- The task that runs after the test tasks ---

abstract class TuistStressNewTestsTask : DefaultTask() {

    @get:Internal
    abstract val mode: Property<String>

    @get:Internal
    abstract val serverUrl: Property<String>

    @get:Internal
    abstract val tuistProject: Property<String>

    @get:Internal
    abstract val useEnvironmentProxy: Property<Boolean>

    @get:Internal
    abstract val projectDir: DirectoryProperty

    @get:Internal
    abstract val gradleUserHomeDir: DirectoryProperty

    @get:Internal
    abstract val gradleHomeDir: DirectoryProperty

    @get:Internal
    abstract val insightsService: Property<TuistTestInsightsService>

    init {
        outputs.upToDateWhen { false }
    }

    @TaskAction
    fun run() {
        val service = insightsService.get()
        val executed = service.executedTestCases()
        if (executed.isEmpty()) return

        val httpClients = TuistHttpClients(useEnvironmentProxy = useEnvironmentProxy.get())
        val configProvider = DefaultConfigurationProvider(
            project = tuistProject.orNull,
            serverUrl = serverUrl.get(),
            projectDir = projectDir.asFile.get(),
            httpClients = httpClients
        )
        val httpClient = TuistHttpClient(
            configurationProvider = configProvider,
            httpClients = httpClients,
            connectTimeoutMs = 10_000,
            readTimeoutMs = 30_000
        )
        val verdictService = TuistStressNewTestsVerdictService(httpClient, serverUrl.get())

        val gate = StressNewTestsGate(
            mode = mode.get(),
            verdict = verdictService::verdict,
            runRepetition = ::runRepetition,
            logger = logger
        )
        val report = gate.run(executed, service.taskPathsByModule()) ?: return
        service.stressNewTestsReport = report

        if (report.blocks) {
            throw GradleException(StressNewTestsGate.blockedMessage(report))
        }
    }

    private fun runRepetition(
        filtersByTaskPath: Map<String, List<String>>,
        repetitions: Int,
        repetition: Int
    ): List<StressRepetitionResult> {
        val outputFile = File.createTempFile("tuist-stress-repetition", ".json")
        outputFile.delete()
        val output = ByteArrayOutputStream()
        val connector = GradleConnector.newConnector()
            .forProjectDirectory(projectDir.asFile.get())
            .useGradleUserHomeDir(gradleUserHomeDir.asFile.get())
        gradleHomeDir.asFile.orNull?.let { connector.useInstallation(it) }
        val connection = connector.connect()
        try {
            connection.newBuild()
                .forTasks(*filtersByTaskPath.keys.toTypedArray())
                .withArguments(
                    "-P${TuistGradleConfig.STRESS_FILTERS_PROPERTY}=${Gson().toJson(filtersByTaskPath)}",
                    "-P${TuistGradleConfig.STRESS_OUTPUT_PROPERTY}=${outputFile.absolutePath}",
                    "--console=plain",
                    "--quiet"
                )
                .setEnvironmentVariables(System.getenv())
                .setStandardOutput(output)
                .setStandardError(output)
                .run()
        } catch (e: Exception) {
            logger.info("Tuist: Stress repetition $repetition of $repetitions output:\n$output")
            throw e
        } finally {
            connection.close()
        }
        if (!outputFile.exists()) {
            logger.info("Tuist: Stress repetition $repetition of $repetitions output:\n$output")
            throw GradleException("the repetition produced no results")
        }
        return try {
            outputFile.reader().use { Gson().fromJson(it, StressRepetitionResults::class.java) }.results
        } finally {
            outputFile.delete()
        }
    }
}
